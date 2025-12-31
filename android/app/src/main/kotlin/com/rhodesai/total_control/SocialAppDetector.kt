package com.rhodesai.total_control

import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Social App Screen Detector for Total Control
 *
 * Detects whether a social app is showing DMs (allowed) or Feed/Browse (blocked).
 * Uses accessibility tree analysis to determine screen type.
 */
object SocialAppDetector {
    private const val TAG = "TotalControl"

    /**
     * Screen types for social apps
     */
    enum class ScreenType {
        DM,              // Direct messages - ALLOWED
        DM_LIST,         // DM inbox/list - ALLOWED
        NOTIFICATIONS,   // Notifications - ALLOWED
        FEED,            // Home feed - BLOCKED
        PROFILE,         // User profiles - BLOCKED
        EXPLORE,         // Explore/discover - BLOCKED
        REELS,           // Short-form video - BLOCKED
        SEARCH,          // Search - BLOCKED
        SETTINGS,        // Settings - ALLOWED
        UNKNOWN          // Unknown - BLOCKED (safe default)
    }

    /**
     * Social apps that need DM/Feed detection
     */
    val SOCIAL_APPS = mapOf(
        // Twitter/X
        "com.twitter.android" to "Twitter",
        "com.twitter.android.lite" to "Twitter Lite",

        // Discord
        "com.discord" to "Discord",

        // Instagram
        "com.instagram.android" to "Instagram",
        "com.instagram.lite" to "Instagram Lite",

        // Facebook
        "com.facebook.katana" to "Facebook",
        "com.facebook.lite" to "Facebook Lite",
        "com.facebook.orca" to "Messenger",  // Messenger is always allowed

        // Reddit
        "com.reddit.frontpage" to "Reddit",
        "com.laurencedawson.reddit_sync" to "Sync for Reddit",
        "com.laurencedawson.reddit_sync.pro" to "Sync Pro",
        "com.andrewshu.android.reddit" to "Reddit is Fun",

        // LinkedIn
        "com.linkedin.android" to "LinkedIn",

        // Snapchat
        "com.snapchat.android" to "Snapchat",

        // Telegram (always allowed - pure messaging)
        "org.telegram.messenger" to "Telegram",

        // WhatsApp (always allowed - pure messaging)
        "com.whatsapp" to "WhatsApp",
        "com.whatsapp.w4b" to "WhatsApp Business",

        // Signal (always allowed - pure messaging)
        "org.thoughtcrime.securesms" to "Signal",
    )

    /**
     * Apps that are purely messaging (always allowed)
     */
    private val PURE_MESSAGING_APPS = setOf(
        "com.facebook.orca",        // Messenger
        "org.telegram.messenger",   // Telegram
        "com.whatsapp",             // WhatsApp
        "com.whatsapp.w4b",         // WhatsApp Business
        "org.thoughtcrime.securesms", // Signal
    )

    /**
     * Detect screen type for a social app
     */
    fun detectScreenType(packageName: String, rootNode: AccessibilityNodeInfo?): ScreenType {
        // Pure messaging apps are always allowed
        if (PURE_MESSAGING_APPS.contains(packageName)) {
            return ScreenType.DM
        }

        if (rootNode == null) {
            Log.w(TAG, "No root node available for screen detection")
            return ScreenType.UNKNOWN
        }

        return when {
            packageName.contains("twitter") -> detectTwitterScreen(rootNode)
            packageName == "com.discord" -> detectDiscordScreen(rootNode)
            packageName.contains("instagram") -> detectInstagramScreen(rootNode)
            packageName.contains("facebook.katana") || packageName.contains("facebook.lite") -> detectFacebookScreen(rootNode)
            packageName.contains("reddit") -> detectRedditScreen(rootNode)
            packageName.contains("linkedin") -> detectLinkedInScreen(rootNode)
            packageName.contains("snapchat") -> detectSnapchatScreen(rootNode)
            else -> ScreenType.UNKNOWN
        }
    }

    /**
     * Twitter/X screen detection
     *
     * DM screens: "Messages" header, conversation view with message bubbles
     * Feed screens: "Home" tab, "For you" / "Following" tabs, tweet cards
     */
    private fun detectTwitterScreen(rootNode: AccessibilityNodeInfo): ScreenType {
        val screenText = extractAllText(rootNode).lowercase()

        // Check for DM indicators
        val dmIndicators = listOf(
            "messages",
            "direct message",
            "new message",
            "message requests",
            "send a message",
            "start a new message"
        )

        // Check for notification indicators
        val notifIndicators = listOf(
            "notifications",
            "all notifications",
            "mentions"
        )

        // Check for feed indicators
        val feedIndicators = listOf(
            "for you",
            "following",
            "what's happening",
            "trending",
            "explore",
            "search twitter",
            "search x",
            "who to follow"
        )

        // DM screen detection - look for message UI elements
        if (hasViewId(rootNode, "com.twitter.android:id/conversation_list") ||
            hasViewId(rootNode, "com.twitter.android:id/message_list") ||
            hasViewId(rootNode, "com.twitter.android:id/compose_message")) {
            return ScreenType.DM
        }

        // Text-based detection
        for (indicator in dmIndicators) {
            if (screenText.contains(indicator) && !screenText.contains("home")) {
                // Make sure we're actually in DM section, not just seeing "messages" button
                if (screenText.contains("conversation") || screenText.contains("chat")) {
                    return ScreenType.DM
                }
            }
        }

        for (indicator in notifIndicators) {
            if (screenText.contains(indicator)) {
                return ScreenType.NOTIFICATIONS
            }
        }

        for (indicator in feedIndicators) {
            if (screenText.contains(indicator)) {
                return ScreenType.FEED
            }
        }

        // Check for profile screen
        if (screenText.contains("followers") && screenText.contains("following") &&
            screenText.contains("posts")) {
            return ScreenType.PROFILE
        }

        // Default to feed (safer)
        return ScreenType.FEED
    }

    /**
     * Discord screen detection
     *
     * DM screens: @username in title, "Direct Messages" header
     * Server screens: #channel-name format, server name visible
     */
    private fun detectDiscordScreen(rootNode: AccessibilityNodeInfo): ScreenType {
        val screenText = extractAllText(rootNode).lowercase()

        // DM indicators
        val dmIndicators = listOf(
            "direct messages",
            "@me",
            "friends",
            "add friend",
            "all friends",
            "pending",
            "blocked"
        )

        // Server/feed indicators
        val serverIndicators = listOf(
            "#",  // Channel names start with #
            "text channels",
            "voice channels",
            "server settings",
            "create channel",
            "browse channels",
            "discover"
        )

        // Check view IDs for DM screen
        if (hasViewId(rootNode, "com.discord:id/private_channels_list") ||
            hasViewId(rootNode, "com.discord:id/direct_message")) {
            return ScreenType.DM
        }

        // Text-based detection
        for (indicator in dmIndicators) {
            if (screenText.contains(indicator)) {
                return ScreenType.DM_LIST
            }
        }

        // Check for server channel (# in title or "text channels" visible)
        for (indicator in serverIndicators) {
            if (screenText.contains(indicator)) {
                return ScreenType.FEED  // Server channels are treated as feed
            }
        }

        // Check notifications
        if (screenText.contains("notifications") || screenText.contains("mentions")) {
            return ScreenType.NOTIFICATIONS
        }

        // Default to blocked
        return ScreenType.UNKNOWN
    }

    /**
     * Instagram screen detection
     *
     * DM screens: "Messages" header, chat bubbles, "Send message"
     * Feed screens: Story tray, posts with hearts/comments, Reels tab
     */
    private fun detectInstagramScreen(rootNode: AccessibilityNodeInfo): ScreenType {
        val screenText = extractAllText(rootNode).lowercase()

        // DM indicators
        val dmIndicators = listOf(
            "messages",
            "send message",
            "new message",
            "message requests",
            "primary",
            "general",
            "requests"
        )

        // Feed indicators
        val feedIndicators = listOf(
            "liked by",
            "comments",
            "view all",
            "suggested for you",
            "sponsored",
            "see translation",
            "story"
        )

        // Reels indicators
        val reelsIndicators = listOf(
            "reels",
            "audio",
            "original audio",
            "trending audio"
        )

        // Explore indicators
        val exploreIndicators = listOf(
            "explore",
            "search",
            "for you",
            "accounts",
            "tags",
            "places"
        )

        // Check view IDs
        if (hasViewId(rootNode, "com.instagram.android:id/direct_thread_list") ||
            hasViewId(rootNode, "com.instagram.android:id/message_content")) {
            return ScreenType.DM
        }

        // Text-based detection - prioritize checking for DM screen
        var isDmLikely = false
        for (indicator in dmIndicators) {
            if (screenText.contains(indicator)) {
                isDmLikely = true
                break
            }
        }

        // If DM indicators found, check if we're actually in DM section
        if (isDmLikely) {
            // Look for chat-specific elements
            if (!screenText.contains("liked by") && !screenText.contains("comments")) {
                return ScreenType.DM
            }
        }

        // Check for Reels
        for (indicator in reelsIndicators) {
            if (screenText.contains(indicator)) {
                return ScreenType.REELS
            }
        }

        // Check for Explore
        for (indicator in exploreIndicators) {
            if (screenText.contains(indicator)) {
                return ScreenType.EXPLORE
            }
        }

        // Check for Feed
        for (indicator in feedIndicators) {
            if (screenText.contains(indicator)) {
                return ScreenType.FEED
            }
        }

        // Check for profile
        if (screenText.contains("posts") && screenText.contains("followers") &&
            screenText.contains("following")) {
            return ScreenType.PROFILE
        }

        // Default to feed
        return ScreenType.FEED
    }

    /**
     * Facebook screen detection
     */
    private fun detectFacebookScreen(rootNode: AccessibilityNodeInfo): ScreenType {
        val screenText = extractAllText(rootNode).lowercase()

        // Messenger/DM indicators
        if (screenText.contains("messenger") || screenText.contains("new message") ||
            screenText.contains("message requests") || screenText.contains("chats")) {
            return ScreenType.DM
        }

        // Feed indicators
        if (screenText.contains("news feed") || screenText.contains("what's on your mind") ||
            screenText.contains("sponsored") || screenText.contains("suggested for you")) {
            return ScreenType.FEED
        }

        // Reels/Watch
        if (screenText.contains("reels") || screenText.contains("watch") ||
            screenText.contains("videos for you")) {
            return ScreenType.REELS
        }

        // Notifications
        if (screenText.contains("notifications")) {
            return ScreenType.NOTIFICATIONS
        }

        return ScreenType.FEED
    }

    /**
     * Reddit screen detection
     */
    private fun detectRedditScreen(rootNode: AccessibilityNodeInfo): ScreenType {
        val screenText = extractAllText(rootNode).lowercase()

        // Chat/DM indicators
        if (screenText.contains("chat") || screenText.contains("inbox") ||
            screenText.contains("messages") || screenText.contains("direct")) {
            return ScreenType.DM
        }

        // Notifications
        if (screenText.contains("notifications") || screenText.contains("activity")) {
            return ScreenType.NOTIFICATIONS
        }

        // Feed indicators
        if (screenText.contains("popular") || screenText.contains("home") ||
            screenText.contains("r/") || screenText.contains("upvote") ||
            screenText.contains("comments") || screenText.contains("share")) {
            return ScreenType.FEED
        }

        return ScreenType.FEED
    }

    /**
     * LinkedIn screen detection
     */
    private fun detectLinkedInScreen(rootNode: AccessibilityNodeInfo): ScreenType {
        val screenText = extractAllText(rootNode).lowercase()

        // Messaging
        if (screenText.contains("messaging") || screenText.contains("new message") ||
            screenText.contains("compose message") || screenText.contains("inmail")) {
            return ScreenType.DM
        }

        // Jobs (allowed)
        if (screenText.contains("jobs") || screenText.contains("apply") ||
            screenText.contains("job alert")) {
            return ScreenType.SETTINGS  // Jobs are allowed
        }

        // Feed
        if (screenText.contains("feed") || screenText.contains("start a post") ||
            screenText.contains("connections")) {
            return ScreenType.FEED
        }

        // Notifications
        if (screenText.contains("notifications")) {
            return ScreenType.NOTIFICATIONS
        }

        return ScreenType.FEED
    }

    /**
     * Snapchat screen detection
     */
    private fun detectSnapchatScreen(rootNode: AccessibilityNodeInfo): ScreenType {
        val screenText = extractAllText(rootNode).lowercase()

        // Chat (DMs are the main screen in Snapchat)
        if (screenText.contains("chat") || screenText.contains("send a chat") ||
            screenText.contains("new chat")) {
            return ScreenType.DM
        }

        // Stories/Spotlight (blocked)
        if (screenText.contains("stories") || screenText.contains("spotlight") ||
            screenText.contains("discover") || screenText.contains("subscriptions")) {
            return ScreenType.FEED
        }

        // Snap Map
        if (screenText.contains("map") || screenText.contains("my location")) {
            return ScreenType.EXPLORE
        }

        // Camera (allowed - it's the main interface)
        if (hasViewId(rootNode, "com.snapchat.android:id/capture_button")) {
            return ScreenType.SETTINGS  // Camera is allowed
        }

        return ScreenType.DM  // Default to DM for Snapchat (chat-first app)
    }

    /**
     * Check if the view tree contains a specific view ID
     */
    private fun hasViewId(node: AccessibilityNodeInfo, viewId: String): Boolean {
        try {
            val nodes = node.findAccessibilityNodeInfosByViewId(viewId)
            return nodes != null && nodes.isNotEmpty()
        } catch (e: Exception) {
            return false
        }
    }

    /**
     * Extract all text from the accessibility tree
     */
    private fun extractAllText(node: AccessibilityNodeInfo): String {
        val textBuilder = StringBuilder()

        node.text?.let { textBuilder.append(it).append(" ") }
        node.contentDescription?.let { textBuilder.append(it).append(" ") }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                textBuilder.append(extractAllText(child))
                child.recycle()
            }
        }

        return textBuilder.toString()
    }

    /**
     * Check if a screen type should be allowed
     */
    fun isAllowed(screenType: ScreenType): Boolean {
        return when (screenType) {
            ScreenType.DM -> true
            ScreenType.DM_LIST -> true
            ScreenType.NOTIFICATIONS -> true
            ScreenType.SETTINGS -> true
            ScreenType.FEED -> false
            ScreenType.PROFILE -> false
            ScreenType.EXPLORE -> false
            ScreenType.REELS -> false
            ScreenType.SEARCH -> false
            ScreenType.UNKNOWN -> false
        }
    }

    /**
     * Get human-readable reason for blocking
     */
    fun getBlockReason(screenType: ScreenType, appName: String): String {
        return when (screenType) {
            ScreenType.FEED -> "$appName feed is blocked.\n\nDirect messages are still allowed."
            ScreenType.PROFILE -> "$appName profiles are blocked.\n\nDirect messages are still allowed."
            ScreenType.EXPLORE -> "$appName explore/discover is blocked.\n\nDirect messages are still allowed."
            ScreenType.REELS -> "$appName reels/short videos are blocked.\n\nDirect messages are still allowed."
            ScreenType.SEARCH -> "$appName search is blocked.\n\nDirect messages are still allowed."
            ScreenType.UNKNOWN -> "$appName is blocked.\n\nOpen direct messages to chat."
            else -> "$appName is blocked."
        }
    }
}
