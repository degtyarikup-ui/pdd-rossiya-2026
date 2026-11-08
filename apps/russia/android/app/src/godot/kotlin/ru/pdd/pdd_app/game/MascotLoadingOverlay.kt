package ru.pdd.pdd_app.game

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Typeface
import android.graphics.drawable.Animatable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.util.concurrent.Executors

/** One shared Flutter asset, decoded incrementally by Android rather than a Godot frame atlas. */
internal class MascotLoadingOverlay(
    context: Context,
    dark: Boolean,
    private val reduceMotion: Boolean,
) : FrameLayout(context) {
    companion object {
        private const val ANIMATION = "flutter_assets/assets/mascot/raster/cone-juggling-384-30.webp"
        private const val POSTER = "flutter_assets/assets/mascot/raster/cone-juggling-poster-384.webp"
    }

    private val image = ImageView(context)
    private val label = TextView(context)
    private val ui = Handler(Looper.getMainLooper())
    private val decoder = Executors.newSingleThreadExecutor { task ->
        Thread(task, "pdd-mascot-decoder").apply { isDaemon = true }
    }
    private var generation = 0
    private var closed = false
    private var foreground = false
    private var decoded: Drawable? = null
    private var decoding = false

    init {
        setBackgroundColor(Color.parseColor(if (dark) "#121214" else "#F8F8FA"))
        isClickable = true
        isFocusable = true
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        val group = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        image.scaleType = ImageView.ScaleType.FIT_CENTER
        image.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        group.addView(image, LinearLayout.LayoutParams(dp(160), dp(160)))
        label.apply {
            setTextColor(Color.parseColor(if (dark) "#8A90A2" else "#A1A6B7"))
            textSize = 14f
            gravity = Gravity.CENTER
            try {
                typeface = Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/Onest-Regular.ttf")
            } catch (_: RuntimeException) { /* System font if a minimal host omits Flutter fonts. */ }
        }
        group.addView(label, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(8)
        })
        addView(group, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        showPoster()
    }

    fun show(message: String) {
        if (closed) return
        label.text = message
        label.visibility = if (message.isEmpty()) View.GONE else View.VISIBLE
        contentDescription = message
        visibility = View.VISIBLE
        bringToFront()
        if (image.drawable == null) showPoster()
        updatePlayback()
    }

    fun hide() {
        if (closed) return
        visibility = View.GONE
        generation += 1
        (decoded as? Animatable)?.stop()
        decoded?.callback = null
        decoded = null
        decoding = false
        // ImageView must not keep an invisible animated drawable scheduled in the game.
        image.setImageDrawable(null)
    }

    fun setForeground(value: Boolean) {
        foreground = value
        updatePlayback()
    }

    private fun updatePlayback() {
        val enabled = !reduceMotion && (Build.VERSION.SDK_INT < 26 || ValueAnimator.areAnimatorsEnabled())
        val play = !closed && foreground && visibility == View.VISIBLE && enabled
        if (!play) {
            (decoded as? Animatable)?.stop()
            return
        }
        if (decoded != null) {
            (decoded as? Animatable)?.start()
            return
        }
        if (Build.VERSION.SDK_INT < 28 || decoding) return
        decoding = true
        val token = generation
        decoder.execute {
            val result = try {
                ImageDecoder.decodeDrawable(ImageDecoder.createSource(context.assets, ANIMATION))
            } catch (failure: Exception) {
                Log.w("PddLoader", "Animated mascot unavailable; keeping poster", failure)
                null
            }
            ui.post {
                if (closed || generation != token || visibility != View.VISIBLE) {
                    (result as? Animatable)?.stop()
                    result?.callback = null
                    return@post
                }
                decoding = false
                decoded = result
                if (result != null) {
                    image.setImageDrawable(result)
                    updatePlayback()
                }
            }
        }
    }

    private fun showPoster() {
        try {
            context.assets.open(POSTER).use { image.setImageBitmap(BitmapFactory.decodeStream(it)) }
        } catch (failure: Exception) {
            Log.w("PddLoader", "Mascot poster unavailable", failure)
        }
    }

    fun close() {
        hide()
        closed = true
        decoder.shutdownNow()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density + 0.5f).toInt()
}
