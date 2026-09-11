package com.example.flutter_app

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.widget.ImageView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Displays the complete ohMY initialization artwork immediately while the
 * Flutter engine starts. MainActivity then reuses this engine, avoiding the
 * long white cold-start window produced by launching Flutter directly.
 */
class SplashActivity : Activity() {
    companion object {
        const val ENGINE_ID = "ohmy_main_engine"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.WHITE
        val artwork = ImageView(this).apply {
            setImageResource(R.drawable.initialize_page)
            scaleType = ImageView.ScaleType.CENTER_CROP
            setBackgroundColor(Color.WHITE)
        }
        setContentView(artwork)

        // Android 12 owns an overlay above the activity. Wait for its real exit
        // callback instead of guessing a delay, remove it, allow the artwork to
        // paint, and only then perform the expensive Flutter engine startup.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { splashView ->
                splashView.remove()
                artwork.postDelayed({ warmFlutterAndContinue() }, 100)
            }
        } else {
            artwork.postDelayed({ warmFlutterAndContinue() }, 100)
        }
    }

    private fun warmFlutterAndContinue() {
        val flutterEngine = FlutterEngine(applicationContext)
        FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine)
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )

        if (!isFinishing && !isDestroyed) {
            startActivity(Intent(this, MainActivity::class.java))
            overridePendingTransition(0, 0)
            finish()
        }
    }
}
