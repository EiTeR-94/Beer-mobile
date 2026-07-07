import AuthenticationServices
import Foundation
import LocalAuthentication
import UIKit

struct PasskeyRegisterResult {
    let accessToken: String
    let user: String
    let label: String?
}

enum PasskeyAuthError: LocalizedError {
    case biometricsUnavailable
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .biometricsUnavailable:
            return "Face ID ou Touch ID requis pour activer l'invitation."
        case .cancelled:
            return "Authentification annulée."
        case .failed(let msg):
            return msg
        }
    }
}

@MainActor
final class PasskeyAuth {
    static let shared = PasskeyAuth()
    static let relyingPartyIdentifier = "eiter.freeboxos.fr"

    private let api = BeerAPI.shared
    private var authController: PasskeyAuthorizationController?

    private init() {}

    static var biometricsAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func register(inviteToken: String) async throws -> PasskeyRegisterResult {
        guard Self.biometricsAvailable else { throw PasskeyAuthError.biometricsUnavailable }

        let options = try await api.passkeyRegisterOptions(inviteToken: inviteToken)
        let challenge = try Self.decodeBase64URL(options.resolvedChallenge)
        let userID = try Self.decodeBase64URL(options.resolvedUserId)
        let rpId = options.resolvedRpId

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: rpId
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: options.resolvedUserName,
            userID: userID
        )
        request.userVerificationPreference = .required
        request.attestationPreference = .none

        let authorization = try await performAuthorization(requests: [request])
        guard let credential = authorization.credential
            as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            throw PasskeyAuthError.failed("Réponse passkey invalide")
        }

        let payload = Self.encodeRegistrationCredential(credential)
        let verified = try await api.passkeyRegisterVerify(inviteToken: inviteToken, credential: payload)
        guard verified.ok != false, let token = verified.accessToken, let user = verified.user else {
            throw PasskeyAuthError.failed(verified.error ?? "Activation passkey refusée")
        }
        return PasskeyRegisterResult(accessToken: token, user: user, label: verified.label)
    }

    func login(username: String) async throws -> String {
        guard Self.biometricsAvailable else { throw PasskeyAuthError.biometricsUnavailable }

        let options = try await api.passkeyLoginOptions(username: username)
        let challenge = try Self.decodeBase64URL(options.resolvedChallenge)
        let rpId = options.resolvedRpId

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: rpId
        )
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.userVerificationPreference = .required
        if let allowed = options.resolvedAllowCredentials, !allowed.isEmpty {
            request.allowedCredentials = allowed.compactMap { item in
                guard let id = Data(base64URLEncoded: item.id) else { return nil }
                return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: id)
            }
        }

        let authorization = try await performAuthorization(requests: [request])
        guard let credential = authorization.credential
            as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw PasskeyAuthError.failed("Réponse passkey invalide")
        }

        let payload = Self.encodeAssertionCredential(credential)
        let verified = try await api.passkeyLoginVerify(credential: payload)
        guard verified.ok != false, let token = verified.accessToken else {
            throw PasskeyAuthError.failed(verified.error ?? "Connexion passkey refusée")
        }
        return token
    }

    private func performAuthorization(requests: [ASAuthorizationRequest]) async throws -> ASAuthorization {
        let controller = PasskeyAuthorizationController()
        authController = controller
        defer { authController = nil }
        do {
            return try await controller.perform(requests: requests)
        } catch let err as PasskeyAuthError {
            throw err
        } catch {
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                throw PasskeyAuthError.cancelled
            }
            throw PasskeyAuthError.failed(error.localizedDescription)
        }
    }

    private static func decodeBase64URL(_ value: String) throws -> Data {
        guard let data = Data(base64URLEncoded: value) else {
            throw PasskeyAuthError.failed("Challenge passkey illisible")
        }
        return data
    }

    private static func encodeRegistrationCredential(
        _ credential: ASAuthorizationPlatformPublicKeyCredentialRegistration
    ) -> [String: Any] {
        [
            "id": credential.credentialID.base64URLEncodedString,
            "rawId": credential.credentialID.base64URLEncodedString,
            "type": "public-key",
            "response": [
                "clientDataJSON": credential.rawClientDataJSON.base64URLEncodedString,
                "attestationObject": credential.rawAttestationObject?.base64URLEncodedString ?? "",
            ],
        ]
    }

    private static func encodeAssertionCredential(
        _ credential: ASAuthorizationPlatformPublicKeyCredentialAssertion
    ) -> [String: Any] {
        var response: [String: Any] = [
            "clientDataJSON": credential.rawClientDataJSON.base64URLEncodedString,
            "authenticatorData": credential.rawAuthenticatorData.base64URLEncodedString,
            "signature": credential.signature.base64URLEncodedString,
        ]
        if let userHandle = credential.userID {
            response["userHandle"] = userHandle.base64URLEncodedString
        }
        return [
            "id": credential.credentialID.base64URLEncodedString,
            "rawId": credential.credentialID.base64URLEncodedString,
            "type": "public-key",
            "response": response,
        ]
    }
}

@MainActor
private final class PasskeyAuthorizationController: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func perform(requests: [ASAuthorizationRequest]) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: requests)
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }

    var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}