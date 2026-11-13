package pe.edu.unjbg.busconectado.core.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import android.view.View
import android.view.ViewGroup
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import org.osmdroid.config.Configuration
import org.osmdroid.events.MapEventsReceiver
import org.osmdroid.events.MapListener
import org.osmdroid.events.ScrollEvent
import org.osmdroid.events.ZoomEvent
import org.osmdroid.tileprovider.tilesource.OnlineTileSourceBase
import org.osmdroid.util.GeoPoint
import org.osmdroid.util.MapTileIndex
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.MapEventsOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline
import pe.edu.unjbg.busconectado.core.location.GeoPointData
import pe.edu.unjbg.busconectado.feature.auth.CameraFocusCommand
import java.io.File

data class MapPolylineSpec(
    val id: String,
    val points: List<GeoPointData>,
    val colorArgb: Int,
    val strokeWidthPx: Float = 10f,
    val dashed: Boolean = false
)

data class MapMarkerSpec(
    val id: String,
    val point: GeoPointData,
    val kind: MapMarkerKind,
    val colorArgb: Int,
    val label: String? = null
)

enum class MapMarkerKind {
    USER_ORIGIN_DOT,
    TRANSIT_STOP_DOT,
    DESTINATION_PIN,
    LIVE_BUS
}

private fun appleDarkOsmFilter(): ColorMatrixColorFilter {
    // Convierte Mapnik claro a estilo oscuro azul-marino Apple Maps preservando tonos naturales (hue-rotate 180)
    val invert = ColorMatrix(
        floatArrayOf(
            -0.96f, 0f, 0f, 0f, 255f,
            0f, -0.96f, 0f, 0f, 255f,
            0f, 0f, -0.96f, 0f, 255f,
            0f, 0f, 0f, 1f, 0f
        )
    )
    val hue180AndNavy = ColorMatrix(
        floatArrayOf(
            -0.574f, 1.430f, 0.144f, 0f, 14f,
            0.426f, 0.430f, 0.144f, 0f, 20f,
            0.426f, 1.430f, -0.856f, 0f, 34f,
            0f, 0f, 0f, 1f, 0f
        )
    )
    val combined = ColorMatrix(hue180AndNavy)
    combined.preConcat(invert)
    return ColorMatrixColorFilter(combined)
}

private val ESRI_WORLD_STREET_MAP: OnlineTileSourceBase = object : OnlineTileSourceBase(
    "EsriWorldStreetMap",
    0,
    19,
    256,
    "",
    arrayOf("https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/"),
    "© Esri"
) {
    override fun getTileURLString(pMapTileIndex: Long): String {
        val zoom = MapTileIndex.getZoom(pMapTileIndex)
        val y = MapTileIndex.getY(pMapTileIndex)
        val x = MapTileIndex.getX(pMapTileIndex)
        return "$baseUrl$zoom/$y/$x"
    }
}

private fun ensureOsmDroidConfigured(context: Context) {
    val config = Configuration.getInstance()
    config.load(context, context.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
    val baseDir = File(context.cacheDir, "osmdroid").apply { mkdirs() }
    val tileDir = File(baseDir, "tiles").apply { mkdirs() }
    config.osmdroidBasePath = baseDir
    config.osmdroidTileCache = tileDir
    config.userAgentValue = "BusConectadoTacna/1.0 (${context.packageName}; Android)"
    config.isDebugTileProviders = false
    config.isDebugMode = false
    config.tileDownloadThreads = 8
    config.tileFileSystemThreads = 4
    config.expirationOverrideDuration = 14L * 24L * 60L * 60L * 1000L
}

@Composable
fun BCOsmMapView(
    modifier: Modifier = Modifier,
    cameraCommand: CameraFocusCommand,
    polylines: List<MapPolylineSpec> = emptyList(),
    markers: List<MapMarkerSpec> = emptyList(),
    onMarkerClick: ((String) -> Unit)? = null,
    onMapTap: ((GeoPointData) -> Unit)? = null,
    onCameraCenterMoved: ((GeoPointData) -> Unit)? = null
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    val mapView = remember {
        ensureOsmDroidConfigured(context)
        MapView(context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setLayerType(View.LAYER_TYPE_HARDWARE, null)
            setTileSource(ESRI_WORLD_STREET_MAP)
            setUseDataConnection(true)
            setMultiTouchControls(true)
            @Suppress("DEPRECATION")
            setBuiltInZoomControls(false)
            isHorizontalMapRepetitionEnabled = false
            isVerticalMapRepetitionEnabled = false
            isTilesScaledToDpi = true
            minZoomLevel = 10.5
            maxZoomLevel = 19.0
            setBackgroundColor(0xFF131A26.toInt())
            overlayManager.tilesOverlay.apply {
                setColorFilter(appleDarkOsmFilter())
                loadingBackgroundColor = 0xFF131A26.toInt()
                loadingLineColor = 0xFF223047.toInt()
            }
            controller.setZoom(cameraCommand.zoom)
            controller.setCenter(GeoPoint(cameraCommand.center.latitude, cameraCommand.center.longitude))
        }
    }

    val lastAppliedNonce = remember { intArrayOf(cameraCommand.nonce) }
    val lastRenderedSignature = remember { arrayOf<Any?>(null, null, false) }

    DisposableEffect(lifecycleOwner, mapView) {
        if (lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            mapView.onResume()
        }
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            mapView.onPause()
            mapView.onDetach()
        }
    }

    AndroidView(
        modifier = modifier,
        factory = {
            mapView.addMapListener(object : MapListener {
                override fun onScroll(event: ScrollEvent?): Boolean {
                    val center = mapView.mapCenter
                    onCameraCenterMoved?.invoke(GeoPointData(center.latitude, center.longitude))
                    return false
                }

                override fun onZoom(event: ZoomEvent?): Boolean {
                    val center = mapView.mapCenter
                    onCameraCenterMoved?.invoke(GeoPointData(center.latitude, center.longitude))
                    return false
                }
            })
            if (lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                mapView.onResume()
            }
            mapView
        },
        update = { mv ->
            if (lastAppliedNonce[0] != cameraCommand.nonce) {
                lastAppliedNonce[0] = cameraCommand.nonce
                val target = GeoPoint(cameraCommand.center.latitude, cameraCommand.center.longitude)
                if (mv.width > 0 && mv.height > 0) {
                    mv.controller.animateTo(target, cameraCommand.zoom, 360L)
                } else {
                    mv.controller.setZoom(cameraCommand.zoom)
                    mv.controller.setCenter(target)
                }
            }

            val hasTap = onMapTap != null
            val needsOverlayRebuild =
                lastRenderedSignature[0] != polylines ||
                    lastRenderedSignature[1] != markers ||
                    lastRenderedSignature[2] != hasTap

            if (needsOverlayRebuild) {
                lastRenderedSignature[0] = polylines
                lastRenderedSignature[1] = markers
                lastRenderedSignature[2] = hasTap

                mv.overlays.clear()

                if (onMapTap != null) {
                    mv.overlays.add(
                        MapEventsOverlay(object : MapEventsReceiver {
                            override fun singleTapConfirmedHelper(p: GeoPoint?): Boolean {
                                p?.let { onMapTap(GeoPointData(it.latitude, it.longitude)) }
                                return true
                            }

                            override fun longPressHelper(p: GeoPoint?): Boolean = false
                        })
                    )
                }

                for (polySpec in polylines) {
                    if (polySpec.points.size < 2) continue
                    val polyline = Polyline(mv).apply {
                        setPoints(polySpec.points.map { GeoPoint(it.latitude, it.longitude) })
                        outlinePaint.color = polySpec.colorArgb
                        outlinePaint.strokeWidth = polySpec.strokeWidthPx
                        outlinePaint.strokeCap = Paint.Cap.ROUND
                        outlinePaint.strokeJoin = Paint.Join.ROUND
                        outlinePaint.isAntiAlias = true
                        if (polySpec.dashed) {
                            outlinePaint.pathEffect = DashPathEffect(floatArrayOf(20f, 16f), 0f)
                        }
                    }
                    mv.overlays.add(polyline)
                }

                for (markerSpec in markers) {
                    val marker = Marker(mv).apply {
                        position = GeoPoint(markerSpec.point.latitude, markerSpec.point.longitude)
                        setAnchor(
                            Marker.ANCHOR_CENTER,
                            if (markerSpec.kind == MapMarkerKind.DESTINATION_PIN) Marker.ANCHOR_BOTTOM else Marker.ANCHOR_CENTER
                        )
                        icon = createMarkerDrawable(context, markerSpec)
                        title = markerSpec.label
                        setOnMarkerClickListener { _, _ ->
                            onMarkerClick?.invoke(markerSpec.id)
                            true
                        }
                    }
                    mv.overlays.add(marker)
                }

                mv.invalidate()
            }
        }
    )
}

private fun createMarkerDrawable(context: Context, spec: MapMarkerSpec): BitmapDrawable {
    val density = context.resources.displayMetrics.density
    return when (spec.kind) {
        MapMarkerKind.USER_ORIGIN_DOT -> {
            val size = (22 * density).toInt().coerceAtLeast(26)
            val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            val cx = size / 2f
            val cy = size / 2f
            val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x552563EB }
            val white = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE }
            val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = spec.colorArgb }
            canvas.drawCircle(cx, cy, cx * 0.92f, glow)
            canvas.drawCircle(cx, cy, cx * 0.62f, white)
            canvas.drawCircle(cx, cy, cx * 0.44f, dot)
            BitmapDrawable(context.resources, bmp)
        }
        MapMarkerKind.TRANSIT_STOP_DOT -> {
            val size = (26 * density).toInt().coerceAtLeast(32)
            val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            val cx = size / 2f
            val cy = size / 2f
            val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE }
            val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = spec.colorArgb }
            val inner = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.WHITE
                textAlign = Paint.Align.CENTER
                textSize = 10f * density
                typeface = Typeface.DEFAULT_BOLD
            }
            canvas.drawCircle(cx, cy, cx * 0.90f, ring)
            canvas.drawCircle(cx, cy, cx * 0.76f, bg)
            canvas.drawText("P", cx, cy + inner.textSize * 0.35f, inner)
            BitmapDrawable(context.resources, bmp)
        }
        MapMarkerKind.DESTINATION_PIN -> {
            val w = (34 * density).toInt().coerceAtLeast(42)
            val h = (42 * density).toInt().coerceAtLeast(50)
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            val cx = w / 2f
            val r = w * 0.38f
            val pinPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = spec.colorArgb }
            val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.WHITE
                style = Paint.Style.STROKE
                strokeWidth = 2.2f * density
            }
            val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE }
            val path = android.graphics.Path().apply {
                moveTo(cx, h - 2f * density)
                lineTo(cx - r * 0.72f, r * 1.35f)
                lineTo(cx + r * 0.72f, r * 1.35f)
                close()
            }
            canvas.drawPath(path, pinPaint)
            canvas.drawCircle(cx, r * 1.05f, r, pinPaint)
            canvas.drawCircle(cx, r * 1.05f, r, border)
            canvas.drawCircle(cx, r * 1.05f, r * 0.36f, dot)
            BitmapDrawable(context.resources, bmp)
        }
        MapMarkerKind.LIVE_BUS -> {
            val size = (34 * density).toInt().coerceAtLeast(42)
            val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            val cx = size / 2f
            val cy = size / 2f
            val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = spec.colorArgb }
            val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.WHITE
                style = Paint.Style.STROKE
                strokeWidth = 2f * density
            }
            val txt = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.WHITE
                textAlign = Paint.Align.CENTER
                textSize = 10f * density
                typeface = Typeface.DEFAULT_BOLD
            }
            canvas.drawCircle(cx, cy, cx * 0.85f, bg)
            canvas.drawCircle(cx, cy, cx * 0.85f, border)
            canvas.drawText(spec.label?.take(3) ?: "BUS", cx, cy + txt.textSize * 0.35f, txt)
            BitmapDrawable(context.resources, bmp)
        }
    }
}
