package fr.eiter.plexibeer.ui

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Size
import android.view.ViewGroup
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size as GeoSize
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import fr.eiter.plexibeer.ui.theme.BeerColors
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Scan EAN live (parité iOS BarcodeScannerView).
 * CameraX preview + ML Kit, debounce 2 s, formats EAN/UPC.
 *
 * [enabled] = false pendant un lookup pour éviter les lectures en rafale.
 */
@Composable
fun LiveBarcodeScanner(
    enabled: Boolean,
    onCode: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val enabledState = rememberUpdatedState(enabled)
    val onCodeState = rememberUpdatedState(onCode)

    val analyzer = remember {
        BarcodeFrameAnalyzer(
            isEnabled = { enabledState.value },
            onCode = { code ->
                hapticTick(context)
                onCodeState.value(code)
            },
        )
    }

    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
    }

    DisposableEffect(lifecycleOwner, previewView) {
        var disposed = false
        val mainExecutor = ContextCompat.getMainExecutor(context)
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            if (disposed) return@addListener
            try {
                val provider = future.get()
                bindCamera(provider, lifecycleOwner, previewView, analyzer)
            } catch (_: Exception) {
                // Caméra indisponible — le parent garde le bouton photo
            }
        }, mainExecutor)

        onDispose {
            disposed = true
            try {
                if (future.isDone) {
                    future.get().unbindAll()
                }
            } catch (_: Exception) {
            }
            analyzer.close()
        }
    }

    Box(modifier = modifier) {
        AndroidView(
            factory = { previewView },
            modifier = Modifier.fillMaxSize(),
        )
        ScanViewfinderOverlay(Modifier.fillMaxSize())
    }
}

private fun bindCamera(
    provider: ProcessCameraProvider,
    lifecycleOwner: LifecycleOwner,
    previewView: PreviewView,
    analyzer: BarcodeFrameAnalyzer,
) {
    val preview = Preview.Builder().build()
    preview.setSurfaceProvider(previewView.surfaceProvider)

    val analysis = ImageAnalysis.Builder()
        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
        .setTargetResolution(Size(1280, 720))
        .build()
    analysis.setAnalyzer(analyzer.executor, analyzer)

    provider.unbindAll()
    provider.bindToLifecycle(
        lifecycleOwner,
        CameraSelector.DEFAULT_BACK_CAMERA,
        preview,
        analysis,
    )
}

/** Overlay cadre + masque sombre + ligne animée (parité iOS ScanViewfinderOverlay). */
@Composable
fun ScanViewfinderOverlay(modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "scanline")
    val linePhase by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(2200, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "scanlinePhase",
    )
    val accent = BeerColors.accent
    val dim = Color.Black.copy(alpha = 0.58f)

    Canvas(modifier = modifier) {
        val fw = size.width * 0.82f
        val fh = size.height * 0.28f
        val left = (size.width - fw) / 2f
        val top = (size.height - fh) / 2f
        val hole = Rect(left, top, left + fw, top + fh)
        val corner = 10f * density

        val holePath = Path().apply {
            addRoundRect(RoundRect(hole, CornerRadius(corner, corner)))
        }

        clipPath(holePath, clipOp = ClipOp.Difference) {
            drawRect(dim)
        }

        drawRoundRect(
            color = accent,
            topLeft = Offset(left, top),
            size = GeoSize(fw, fh),
            cornerRadius = CornerRadius(corner, corner),
            style = Stroke(width = 2f * density),
        )

        val arm = 14f * density
        val sw = 2.5f * density
        drawLine(accent, Offset(left, top + arm), Offset(left, top), strokeWidth = sw, cap = StrokeCap.Round)
        drawLine(accent, Offset(left, top), Offset(left + arm, top), strokeWidth = sw, cap = StrokeCap.Round)
        drawLine(accent, Offset(left + fw - arm, top), Offset(left + fw, top), strokeWidth = sw, cap = StrokeCap.Round)
        drawLine(accent, Offset(left + fw, top), Offset(left + fw, top + arm), strokeWidth = sw, cap = StrokeCap.Round)
        drawLine(accent, Offset(left, top + fh - arm), Offset(left, top + fh), strokeWidth = sw, cap = StrokeCap.Round)
        drawLine(accent, Offset(left, top + fh), Offset(left + arm, top + fh), strokeWidth = sw, cap = StrokeCap.Round)
        drawLine(accent, Offset(left + fw - arm, top + fh), Offset(left + fw, top + fh), strokeWidth = sw, cap = StrokeCap.Round)
        drawLine(accent, Offset(left + fw, top + fh - arm), Offset(left + fw, top + fh), strokeWidth = sw, cap = StrokeCap.Round)

        val lineY = top + fh * 0.12f + linePhase * (fh * 0.76f)
        val lineHalf = fw * 0.44f
        val cx = size.width / 2f
        drawLine(
            brush = Brush.horizontalGradient(
                colors = listOf(Color.Transparent, accent, Color.Transparent),
                startX = cx - lineHalf,
                endX = cx + lineHalf,
            ),
            start = Offset(cx - lineHalf, lineY),
            end = Offset(cx + lineHalf, lineY),
            strokeWidth = 2f * density,
            pathEffect = PathEffect.cornerPathEffect(2f),
        )
    }
}

@OptIn(ExperimentalGetImage::class)
private class BarcodeFrameAnalyzer(
    private val isEnabled: () -> Boolean,
    private val onCode: (String) -> Unit,
) : ImageAnalysis.Analyzer {
    val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "beer-barcode-mlkit").apply { isDaemon = true }
    }

    private val scanner: BarcodeScanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(
                Barcode.FORMAT_EAN_13,
                Barcode.FORMAT_EAN_8,
                Barcode.FORMAT_UPC_A,
                Barcode.FORMAT_UPC_E,
            )
            .build(),
    )

    private val processing = AtomicBoolean(false)
    private val mainLock = Any()
    private var lastCode = ""
    private var lastAtMs = 0L
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun analyze(imageProxy: ImageProxy) {
        if (!isEnabled() || !processing.compareAndSet(false, true)) {
            imageProxy.close()
            return
        }

        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            processing.set(false)
            imageProxy.close()
            return
        }

        val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        scanner.process(image)
            .addOnSuccessListener { barcodes ->
                if (!isEnabled()) return@addOnSuccessListener
                val raw = barcodes.firstOrNull { b ->
                    val f = b.format
                    (f == Barcode.FORMAT_EAN_13 ||
                        f == Barcode.FORMAT_EAN_8 ||
                        f == Barcode.FORMAT_UPC_A ||
                        f == Barcode.FORMAT_UPC_E) &&
                        !b.rawValue.isNullOrBlank()
                }?.rawValue ?: barcodes.firstOrNull { !it.rawValue.isNullOrBlank() }?.rawValue

                if (raw.isNullOrBlank()) return@addOnSuccessListener
                val code = raw.filter { it.isDigit() }
                if (code.length < 8) return@addOnSuccessListener

                val now = System.currentTimeMillis()
                val accept = synchronized(mainLock) {
                    val sameRecent = code == lastCode && (now - lastAtMs) <= 2000L
                    if (sameRecent) {
                        false
                    } else {
                        lastCode = code
                        lastAtMs = now
                        true
                    }
                }
                if (accept) {
                    mainHandler.post {
                        if (isEnabled()) onCode(code)
                    }
                }
            }
            .addOnCompleteListener {
                processing.set(false)
                imageProxy.close()
            }
    }

    fun close() {
        try {
            scanner.close()
        } catch (_: Exception) {
        }
        try {
            executor.shutdown()
        } catch (_: Exception) {
        }
    }
}

private fun hapticTick(context: Context) {
    try {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vm.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(40, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(40)
        }
    } catch (_: Exception) {
    }
}
