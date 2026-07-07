package fr.eiter.plexibeer

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import android.widget.TextView
import android.widget.LinearLayout
import android.widget.Button
import android.view.ViewGroup

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL
        layout.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        val text = TextView(this)
        text.text = "PlexiBeer Android\n\nSame as iOS native:\n- Local accounts: LAN path\n- Guests: 5G path\n\nAPK ready for test on PC emulator."
        layout.addView(text)
        val btn = Button(this)
        btn.text = "Test LAN mode"
        btn.setOnClickListener {
            text.text = "Using LAN base: ${ServerSettings.lanApiBase}"
        }
        layout.addView(btn)
        setContentView(layout)
    }
}