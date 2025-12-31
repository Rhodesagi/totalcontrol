package com.rhodesai.total_control

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.PixelFormat
import android.os.Build
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Total Control Accessibility Service
 *
 * Monitors app usage and blocks distracting content while allowing messaging.
 *
 * Logic:
 * 1. Social app opened → Detect if DM screen or Feed screen
 * 2. DM/Messages → ALLOW
 * 3. Feed/Explore/Reels → BLOCK
 * 4. Streaming apps → Check syllabus or block
 * 5. Browser → Check URL patterns
 */
class BlockerAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "TotalControl"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_BLOCKER_ENABLED = "flutter.blocker_enabled"
    }

    private var overlayView: View? = null
    private var windowManager: WindowManager? = null
    private var lastBlockedApp: String? = null
    private var lastScreenType: SocialAppDetector.ScreenType? = null
    private lateinit var prefs: SharedPreferences

    // Browser URL bar IDs for web blocking
    private val browserUrlBarIds = mapOf(
        "com.android.chrome" to "com.android.chrome:id/url_bar",
        "com.chrome.beta" to "com.chrome.beta:id/url_bar",
        "org.mozilla.firefox" to "org.mozilla.firefox:id/mozac_browser_toolbar_url_view",
        "com.brave.browser" to "com.brave.browser:id/url_bar",
        "com.opera.browser" to "com.opera.browser:id/url_field",
        "com.microsoft.emmx" to "com.microsoft.emmx:id/url_bar",
        "com.sec.android.app.sbrowser" to "com.sec.android.app.sbrowser:id/location_bar_edit_text",
        "com.duckduckgo.mobile.android" to "com.duckduckgo.mobile.android:id/omnibarTextInput",
    )

    // Streaming apps - always blocked (except music)
    private val streamingApps = setOf(
        "com.netflix.mediaclient",
        "com.google.android.youtube",
        "com.amazon.avod.thirdpartyclient",
        "com.disney.disneyplus",
        "com.hulu.plus",
        "com.wbd.stream",
        "tv.twitch.android.app",
        "com.zhiliaoapp.musically",  // TikTok
        "com.ss.android.ugc.trill",  // TikTok
        "com.crunchyroll.crunchyroid",
        "com.peacocktv.peacockandroid",
    )

    // Always allowed apps
    private val alwaysAllowedApps = setOf(
        "com.google.android.apps.youtube.music",  // YouTube Music
        "com.spotify.music",                       // Spotify
        "com.apple.android.music",                 // Apple Music
        "com.amazon.mp3",                          // Amazon Music
        "deezer.android.app",                      // Deezer
        "com.pandora.android",                     // Pandora
        "com.soundcloud.android",                  // SoundCloud
        "com.rhodesai.total_control",              // This app
        "com.android.settings",
        "com.android.systemui",
    )

    // System/launcher apps - always allowed
    private val systemApps = setOf(
        "com.google.android.apps.nexuslauncher",
        "com.google.android.launcher",
        "com.sec.android.app.launcher",
        "com.miui.home",
        "com.huawei.android.launcher",
        "com.oppo.launcher",
        "com.android.launcher",
        "com.android.launcher3",
        "com.android.packageinstaller",
        "com.android.permissioncontroller",
        "com.android.vending",
        "com.google.android.packageinstaller",
    )

    override fun onCreate() {
        super.onCreate()
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        Log.i(TAG, "TotalControl Accessibility Service created")
    }

    private fun isBlockerEnabled(): Boolean {
        return prefs.getBoolean(KEY_BLOCKER_ENABLED, true)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (!isBlockerEnabled()) {
            hideOverlay()
            return
        }

        val packageName = event.packageName?.toString() ?: return

        // System apps - always allow
        if (systemApps.contains(packageName)) {
            hideOverlay()
            return
        }

        // Always allowed apps (music, etc.)
        if (alwaysAllowedApps.contains(packageName)) {
            hideOverlay()
            return
        }

        // SOCIAL APPS - DM vs Feed detection
        if (SocialAppDetector.SOCIAL_APPS.containsKey(packageName)) {
            handleSocialApp(packageName, event)
            return
        }

        // Streaming apps - block entirely
        if (streamingApps.contains(packageName)) {
            val appName = getAppName(packageName)
            showOverlay("$appName is blocked.\n\nFocus on your goals.")
            return
        }

        // Browsers - check URL
        if (browserUrlBarIds.containsKey(packageName)) {
            when (event.eventType) {
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                    checkBrowserUrl(packageName)
                }
            }
            return
        }

        // Everything else - allow
        hideOverlay()
    }

    /**
     * Handle social app - detect DM vs Feed screen
     */
    private fun handleSocialApp(packageName: String, event: AccessibilityEvent) {
        val appName = SocialAppDetector.SOCIAL_APPS[packageName] ?: packageName

        // Only check on significant events
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            return
        }

        val rootNode = rootInActiveWindow
        if (rootNode == null) {
            // Can't read screen - show overlay briefly then check again
            if (lastBlockedApp != packageName) {
                showOverlay("$appName - detecting screen...")
            }
            return
        }

        try {
            // Detect screen type
            val screenType = SocialAppDetector.detectScreenType(packageName, rootNode)

            Log.d(TAG, "$appName screen type: $screenType")

            if (SocialAppDetector.isAllowed(screenType)) {
                // DMs/Notifications allowed
                hideOverlay()
                lastBlockedApp = null
                lastScreenType = null
            } else {
                // Feed/Explore/Reels blocked
                val reason = SocialAppDetector.getBlockReason(screenType, appName)

                // Only update overlay if screen changed
                if (lastBlockedApp != packageName || lastScreenType != screenType) {
                    showOverlay(reason)
                    lastBlockedApp = packageName
                    lastScreenType = screenType
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error detecting social app screen: ${e.message}")
            // On error, allow access (fail open for usability)
            hideOverlay()
        } finally {
            rootNode.recycle()
        }
    }

    /**
     * Check browser URL for blocked sites
     */
    private fun checkBrowserUrl(packageName: String) {
        val urlBarId = browserUrlBarIds[packageName] ?: return
        val rootNode = rootInActiveWindow ?: return

        try {
            val urlNodes = rootNode.findAccessibilityNodeInfosByViewId(urlBarId)
            val url = urlNodes?.firstOrNull()?.text?.toString()

            if (url != null && url.isNotEmpty()) {
                val blockResult = shouldBlockUrl(url.lowercase())
                if (blockResult != null) {
                    showOverlay(blockResult)
                } else {
                    hideOverlay()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error reading browser URL: ${e.message}")
        } finally {
            rootNode.recycle()
        }
    }

    /**
     * Check if URL should be blocked and return block reason, or null if allowed
     */
    private fun shouldBlockUrl(url: String): String? {
        // YouTube Music - always allowed
        if (url.contains("music.youtube.com")) {
            return null
        }

        // YouTube - check for music video or block
        if (url.contains("youtube.com") || url.contains("youtu.be")) {
            // Allow search (to find music)
            if (url.contains("/results") || url.contains("search_query")) {
                return null
            }
            return "YouTube is blocked.\n\nMusic videos and YouTube Music are still allowed."
        }

        // Twitter/X - check for DMs
        if (url.contains("twitter.com") || url.contains("x.com")) {
            if (url.contains("/messages") || url.contains("/i/chat") ||
                url.contains("/notifications")) {
                return null  // DMs allowed
            }
            return "Twitter/X feed is blocked.\n\nDirect messages are still allowed."
        }

        // Discord - check for DMs
        if (url.contains("discord.com")) {
            if (url.contains("/channels/@me")) {
                return null  // DMs allowed
            }
            return "Discord servers are blocked.\n\nDirect messages are still allowed."
        }

        // Instagram
        if (url.contains("instagram.com")) {
            if (url.contains("/direct")) {
                return null  // DMs allowed
            }
            return "Instagram is blocked.\n\nDirect messages are still allowed."
        }

        // Reddit
        if (url.contains("reddit.com")) {
            if (url.contains("/message") || url.contains("/chat")) {
                return null
            }
            return "Reddit is blocked.\n\nMessages are still allowed."
        }

        // Facebook
        if (url.contains("facebook.com")) {
            if (url.contains("/messages") || url.contains("messenger.com")) {
                return null
            }
            return "Facebook is blocked.\n\nMessenger is still allowed."
        }

        // Streaming sites
        val streamingSites = listOf(
            "netflix.com", "hulu.com", "disneyplus.com", "max.com",
            "primevideo.com", "twitch.tv", "tiktok.com"
        )
        for (site in streamingSites) {
            if (url.contains(site)) {
                return "${site.split(".")[0].capitalize()} is blocked.\n\nFocus on your goals."
            }
        }

        return null  // Allow everything else
    }

    private fun getAppName(packageName: String): String {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            packageName.split(".").last().capitalize()
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "TotalControl service interrupted")
    }

    private fun showOverlay(message: String) {
        if (overlayView != null) {
            overlayView?.findViewById<TextView>(R.id.blocking_message)?.text = message
            return
        }

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.CENTER

        // Create overlay programmatically
        overlayView = createOverlayView(message)

        try {
            windowManager?.addView(overlayView, params)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}")
        }
    }

    private fun createOverlayView(message: String): View {
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(0xF0121210.toInt())  // Dark semi-transparent
            setPadding(48, 48, 48, 48)
        }

        // Title
        val title = TextView(this).apply {
            text = "TOTAL CONTROL"
            textSize = 28f
            setTextColor(0xFFFFB000.toInt())  // Amber
            gravity = Gravity.CENTER
            letterSpacing = 0.1f
        }
        layout.addView(title)

        // Subtitle
        val subtitle = TextView(this).apply {
            text = "A Rhodes Program"
            textSize = 12f
            setTextColor(0xFF6B6348.toInt())  // Dim
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 48)
        }
        layout.addView(subtitle)

        // Lock icon (using text emoji)
        val icon = TextView(this).apply {
            text = "\uD83D\uDD12"  // Lock emoji
            textSize = 64f
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 32)
        }
        layout.addView(icon)

        // Message
        val messageView = TextView(this).apply {
            id = R.id.blocking_message
            text = message
            textSize = 18f
            setTextColor(0xFFD4C4A0.toInt())  // Light text
            gravity = Gravity.CENTER
            setPadding(32, 32, 32, 32)
        }
        layout.addView(messageView)

        // Open TotalControl button
        val button = Button(this).apply {
            text = "Open TotalControl"
            setOnClickListener {
                val intent = packageManager.getLaunchIntentForPackage("com.rhodesai.total_control")
                intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (intent != null) {
                    startActivity(intent)
                }
            }
        }
        layout.addView(button)

        return layout
    }

    private fun hideOverlay() {
        overlayView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                Log.e(TAG, "Error hiding overlay: ${e.message}")
            }
            overlayView = null
        }
        lastBlockedApp = null
        lastScreenType = null
    }

    override fun onDestroy() {
        super.onDestroy()
        hideOverlay()
        Log.i(TAG, "TotalControl Accessibility Service destroyed")
    }
}
