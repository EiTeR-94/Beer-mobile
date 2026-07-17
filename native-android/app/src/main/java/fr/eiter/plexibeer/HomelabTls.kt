package fr.eiter.plexibeer

import android.util.Log
import okhttp3.OkHttpClient
import java.security.KeyStore
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/**
 * Homelab TLS helpers mirroring iOS HomelabTLSDelegate:
 * - For LAN private IPs: accept if cert is valid for eiter.freeboxos.fr (SAN domain mismatch).
 * - For public domain: system default hostname verification.
 * Still requires a valid public CA chain (Let's Encrypt) — not trust-all.
 */
object HomelabTls {
    private const val TAG = "HomelabTls"
    private const val PIN_DOMAIN = "eiter.freeboxos.fr"

    fun systemTrustManager(): X509TrustManager {
        val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        tmf.init(null as KeyStore?)
        return tmf.trustManagers.filterIsInstance<X509TrustManager>().first()
    }

    /**
     * Trust manager that validates the chain normally, but for LAN hosts does not
     * fail solely on hostname (hostname is handled separately / via domain check).
     */
    fun trustManager(): X509TrustManager {
        val system = systemTrustManager()
        return object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                system.checkClientTrusted(chain, authType)
            }

            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                if (chain.isNullOrEmpty()) throw CertificateException("empty chain")
                // Always require a valid chain against system roots
                system.checkServerTrusted(chain, authType)
            }

            override fun getAcceptedIssuers(): Array<X509Certificate> = system.acceptedIssuers
        }
    }

    fun hostnameVerifier(): HostnameVerifier {
        val default = HostnameVerifier { hostname, session ->
            javax.net.ssl.HttpsURLConnection.getDefaultHostnameVerifier().verify(hostname, session)
        }
        return HostnameVerifier { hostname, session ->
            if (default.verify(hostname, session)) return@HostnameVerifier true
            // LAN IP: accept if cert is valid for our domain (same compromise as iOS)
            if (ServerSettings.isLanHost(hostname)) {
                val ok = default.verify(PIN_DOMAIN, session)
                if (ok) Log.i(TAG, "accepted LAN IP $hostname with domain policy $PIN_DOMAIN")
                else Log.w(TAG, "domain policy failed for LAN IP $hostname")
                return@HostnameVerifier ok
            }
            // WAN IPv4 direct (4G fallback) : cert Let's Encrypt pour eiter.freeboxos.fr
            if (hostname == ServerSettings.WAN_IPV4) {
                val ok = default.verify(PIN_DOMAIN, session)
                if (ok) Log.i(TAG, "accepted WAN IPv4 $hostname with SNI domain $PIN_DOMAIN")
                else Log.w(TAG, "domain policy failed for WAN IPv4 $hostname")
                return@HostnameVerifier ok
            }
            false
        }
    }

    fun applyTo(builder: OkHttpClient.Builder): OkHttpClient.Builder {
        val tm = trustManager()
        val ctx = SSLContext.getInstance("TLS")
        ctx.init(null, arrayOf(tm), null)
        return builder
            .sslSocketFactory(ctx.socketFactory, tm)
            .hostnameVerifier(hostnameVerifier())
    }
}
