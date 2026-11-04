package com.example.kazumi

import android.app.Activity
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Rect
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.PixelCopy
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.catalog.components.LiquidBottomTab
import com.kyant.backdrop.catalog.components.LiquidBottomTabs
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import kotlin.math.ceil
import kotlin.math.roundToInt

/** Owns the official Compose component; PixelCopy excludes the native overlay. */
class LiquidNavigationHost(private val activity: Activity, private val channel: MethodChannel) {
    private val parent get() = activity.findViewById<FrameLayout>(android.R.id.content)
    private val handler = Handler(Looper.getMainLooper())
    private val owner = NavigationOwner()
    private var view: ComposeView? = null
    private var selectedIndex by mutableIntStateOf(0)
    private var labels by mutableStateOf(List(4) { "" })
    private var icons by mutableStateOf(List(4) { 0 })
    private var dark by mutableStateOf(true)
    private var rtl by mutableStateOf(false)
    private var textScale by mutableStateOf(1f)
    private var barWidth by mutableIntStateOf(0)
    private var frame by mutableStateOf<BackdropFrame?>(null)
    private val buffers = mutableListOf<Bitmap>()
    private var bufferIndex = 0
    private var crop = Rect()
    private var desiredCrop = Rect()
    private var visible = false
    private var disposed = false
    private var dirty = false
    private var scheduled = false
    private var copying = false
    private var captured = 0L
    private var failures = 0L
    private var copyNanos = 0L
    private val captureRunnable = Runnable { scheduled = false; capture() }
    private val typeface by lazy {
        val manifest = JSONArray(activity.assets.open("flutter_assets/FontManifest.json").bufferedReader().use { it.readText() })
        val font = (0 until manifest.length()).asSequence().map { manifest.getJSONObject(it) }
            .first { it.getString("family") == "packages/lucide_icons_flutter/Lucide" }
            .getJSONArray("fonts").getJSONObject(0).getString("asset")
        FontFamily(Typeface.createFromAsset(activity.assets, "flutter_assets/$font"))
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> result.success(Build.VERSION.SDK_INT >= 33)
            "update" -> {
                @Suppress("UNCHECKED_CAST")
                update(call.arguments as Map<String, Any?>)
                result.success(null)
            }
            "invalidateBackdrop" -> { invalidateBackdrop(); result.success(null) }
            "hide" -> { hide(); result.success(null) }
            "diagnostics" -> result.success(mapOf(
                "library" to "io.github.kyant0:backdrop:2.0.1",
                "component" to "LiquidBottomTabs",
                "visible" to visible,
                "selectedIndex" to selectedIndex,
                "captures" to captured,
                "failures" to failures,
                "meanCopyMs" to if (captured == 0L) 0.0 else copyNanos / captured / 1_000_000.0,
                "samplingPixels" to listOf(crop.width(), crop.height()),
                "source" to sourceSurface()?.javaClass?.simpleName,
                "view" to view?.javaClass?.name
            ))
            "dispose" -> { hide(); view?.disposeComposition(); view?.let(parent::removeView); view = null; result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun update(data: Map<String, Any?>) {
        if (disposed || Build.VERSION.SDK_INT < 33) return
        selectedIndex = (data["selectedIndex"] as Number).toInt().coerceIn(0, 3)
        labels = List(4) { data["label$it"] as String }
        icons = List(4) { (data["icon$it"] as Number).toInt() }
        dark = data["dark"] == true
        rtl = data["rtl"] == true
        textScale = (data["textScale"] as Number).toFloat().coerceIn(1f, 1.3f)
        if (data["visible"] != true) { hide(); return }
        val source = sourceSurface() ?: return
        // The upstream pressed lens can extend beyond its slot during a fling.
        val margin = ceil(48 * activity.resources.displayMetrics.density).toInt()
        val left = (data["left"] as Number).toDouble().roundToInt()
        val top = (data["top"] as Number).toDouble().roundToInt()
        val width = (data["width"] as Number).toDouble().roundToInt()
        val height = (data["height"] as Number).toDouble().roundToInt()
        barWidth = width
        val requested = Rect(left - margin, top - margin, left + width + margin, top + height + margin)
        val region = Rect(requested)
        if (!region.intersect(0, 0, source.width, source.height)) return
        val surfaceLocation = IntArray(2).also(source::getLocationInWindow)
        val parentLocation = IntArray(2).also(parent::getLocationInWindow)
        val nativeView = view ?: ComposeView(activity).also {
            it.setViewTreeLifecycleOwner(owner)
            it.setViewTreeSavedStateRegistryOwner(owner)
            it.clipChildren = false
            it.clipToPadding = false
            it.setContent { NavigationContent() }
            parent.addView(it)
            view = it
        }
        nativeView.layoutParams = FrameLayout.LayoutParams(requested.width(), requested.height(), Gravity.TOP or Gravity.LEFT).apply {
            leftMargin = requested.left + surfaceLocation[0] - parentLocation[0]
            topMargin = requested.top + surfaceLocation[1] - parentLocation[1]
        }
        val changed = requested != desiredCrop || region != crop
        desiredCrop = requested
        crop = region
        visible = true
        nativeView.visibility = View.VISIBLE
        if (changed) frame = null
        invalidateBackdrop()
    }

    @Composable
    private fun NavigationContent() {
        val density = LocalDensity.current
        val configuration = Configuration(LocalConfiguration.current).apply {
            uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                if (dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
        }
        CompositionLocalProvider(
            LocalConfiguration provides configuration,
            LocalDensity provides Density(density.density, textScale),
            LocalLayoutDirection provides if (rtl) LayoutDirection.Rtl else LayoutDirection.Ltr
        ) {
            val background = rememberLayerBackdrop()
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize().clearAndSetSemantics {}.alpha(0f).layerBackdrop(background)) {
                    frame?.let { current -> drawImage(current.bitmap.asImageBitmap(), topLeft = current.offset) }
                }
                // The sample remembers its drag width inside its animation scope.
                key(barWidth, density.density, textScale, rtl) {
                    LiquidBottomTabs(
                        selectedTabIndex = { selectedIndex },
                        onTabSelected = ::select,
                        backdrop = background,
                        tabsCount = 4,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 48.dp)
                    ) {
                        repeat(4) { index ->
                            LiquidBottomTab(
                                onClick = { select(index) },
                                modifier = Modifier.semantics { selected = index == selectedIndex }
                            ) {
                                BasicText(
                                    String(Character.toChars(icons[index])),
                                    modifier = Modifier.clearAndSetSemantics {},
                                    style = TextStyle(color = Color(0xFFE6EAF2), fontFamily = typeface, fontSize = 20.sp)
                                )
                                BasicText(labels[index], style = TextStyle(color = Color(0xFFE6EAF2), fontSize = 11.5f.sp))
                            }
                        }
                    }
                }
            }
        }
    }

    private fun select(index: Int) {
        if (index == selectedIndex) return
        selectedIndex = index
        channel.invokeMethod("selectTab", index)
    }

    fun invalidateBackdrop() {
        if (disposed || !visible) return
        dirty = true
        if (scheduled || copying) return
        scheduled = true
        view?.postOnAnimation(captureRunnable)
    }

    private fun capture() {
        if (disposed || !visible || !dirty || copying) return
        val source = sourceSurface() ?: return
        if (!source.holder.surface.isValid || crop.isEmpty) return
        dirty = false
        copying = true
        val region = Rect(crop)
        val requested = Rect(desiredCrop)
        if (buffers.firstOrNull()?.let { it.width != region.width() || it.height != region.height() } != false) {
            buffers.clear()
            repeat(3) { buffers += Bitmap.createBitmap(region.width(), region.height(), Bitmap.Config.ARGB_8888) }
            bufferIndex = 0
        }
        val bitmap = buffers[bufferIndex]
        bufferIndex = (bufferIndex + 1) % buffers.size
        val started = System.nanoTime()
        try {
            PixelCopy.request(source, region, bitmap, { status ->
                copying = false
                if (disposed || !visible) return@request
                if (region != crop || requested != desiredCrop) {
                    invalidateBackdrop()
                    return@request
                }
                if (status == PixelCopy.SUCCESS) {
                    frame = BackdropFrame(bitmap, Offset((region.left - requested.left).toFloat(), (region.top - requested.top).toFloat()))
                    captured++
                    copyNanos += System.nanoTime() - started
                    if (captured == 1L) Log.i("PlayraLiquidGlass", "Official Backdrop 2.0.1 / LiquidBottomTabs / FlutterSurfaceView ${region.width()}x${region.height()}")
                } else {
                    failures++
                }
                if (dirty) invalidateBackdrop()
            }, handler)
        } catch (error: IllegalArgumentException) {
            copying = false
            failures++
        }
    }

    private fun sourceSurface(): FlutterSurfaceView? {
        fun find(root: View): FlutterSurfaceView? {
            if (root is FlutterSurfaceView) return root
            if (root is ViewGroup) repeat(root.childCount) { find(root.getChildAt(it))?.let { found -> return found } }
            return null
        }
        return find(parent)
    }

    fun hide() {
        visible = false
        dirty = false
        scheduled = false
        view?.removeCallbacks(captureRunnable)
        view?.visibility = View.GONE
    }

    fun onResume() { owner.registry.currentState = Lifecycle.State.RESUMED }
    fun onPause() { owner.registry.currentState = Lifecycle.State.CREATED; hide() }

    fun dispose() {
        hide()
        disposed = true
        view?.disposeComposition()
        view?.let(parent::removeView)
        view = null
        frame = null
        buffers.clear()
        owner.registry.currentState = Lifecycle.State.DESTROYED
        channel.setMethodCallHandler(null)
    }

    private data class BackdropFrame(val bitmap: Bitmap, val offset: Offset)

    private class NavigationOwner : LifecycleOwner, SavedStateRegistryOwner {
        val registry = LifecycleRegistry(this)
        private val state = SavedStateRegistryController.create(this)
        override val lifecycle get() = registry
        override val savedStateRegistry get() = state.savedStateRegistry
        init {
            state.performAttach()
            state.performRestore(null)
            registry.currentState = Lifecycle.State.CREATED
        }
    }
}
