#!/usr/bin/env python3
"""
TotalControl Desktop Window Monitor

Monitors desktop app windows (Discord, Slack, etc.) and detects
DM vs Feed/Server screens based on window titles.

Discord window titles:
- DM: "@username - Discord" or "Discord"
- Server: "#channel-name - Server Name - Discord"

Usage:
    python window_monitor.py [--daemon]
"""

import subprocess
import re
import time
import sys
import os
from dataclasses import dataclass
from enum import Enum
from typing import Optional, Tuple

class ScreenType(Enum):
    DM = "dm"
    DM_LIST = "dm_list"
    SERVER_CHANNEL = "server_channel"
    FEED = "feed"
    UNKNOWN = "unknown"
    ALLOWED = "allowed"

@dataclass
class WindowInfo:
    window_id: str
    pid: int
    wm_class: str
    title: str

@dataclass
class BlockDecision:
    should_block: bool
    reason: str
    app_name: str
    screen_type: ScreenType

# App detection patterns
APP_PATTERNS = {
    # Discord
    'discord': {
        'wm_class': ['discord', 'Discord'],
        'dm_patterns': [
            r'^@[\w\s]+ - Discord$',           # DM conversation: @username - Discord
            r'^Discord$',                        # Home/DM list
            r'^Friends - Discord$',              # Friends list
            r'^[\w\s]+ and \d+ others? - Discord$',  # Group DM
        ],
        'server_patterns': [
            r'^#[\w-]+ - .+ - Discord$',        # Server channel: #channel - Server - Discord
            r'^.+ - Discord$',                   # Could be server (if not matched above)
        ],
    },
    # Slack
    'slack': {
        'wm_class': ['slack', 'Slack'],
        'dm_patterns': [
            r'^\* .+ \| Slack$',                 # DM with unread
            r'^[\w\s]+ \| Slack$',               # DM conversation (name only)
        ],
        'server_patterns': [
            r'^#[\w-]+ \| .+ \| Slack$',        # Channel
        ],
    },
    # Twitter/X (Electron app if exists)
    'twitter': {
        'wm_class': ['twitter', 'Twitter', 'TweetDeck'],
        'dm_patterns': [
            r'Messages',
            r'Direct Messages',
        ],
        'server_patterns': [
            r'Home',
            r'Explore',
            r'Notifications',  # Could argue this should be allowed
        ],
    },
}

# Always allowed apps
ALLOWED_APPS = {
    'spotify', 'Spotify',
    'rhythmbox', 'Rhythmbox',
    'vlc', 'VLC',
    'telegram-desktop', 'TelegramDesktop', 'Telegram',
    'signal', 'Signal',
    'element', 'Element',
    'whatsapp', 'WhatsApp',
}

# Always blocked apps (no DM exception)
BLOCKED_APPS = {
    'netflix',
    'tiktok',
}


def get_active_window() -> Optional[WindowInfo]:
    """Get currently focused window info using xdotool and xprop"""
    try:
        # Get active window ID
        result = subprocess.run(
            ['xdotool', 'getactivewindow'],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode != 0:
            return None

        window_id = result.stdout.strip()

        # Get window name
        result = subprocess.run(
            ['xdotool', 'getwindowname', window_id],
            capture_output=True, text=True, timeout=2
        )
        title = result.stdout.strip() if result.returncode == 0 else ""

        # Get window PID
        result = subprocess.run(
            ['xdotool', 'getwindowpid', window_id],
            capture_output=True, text=True, timeout=2
        )
        pid = int(result.stdout.strip()) if result.returncode == 0 else 0

        # Get WM_CLASS using xprop
        result = subprocess.run(
            ['xprop', '-id', window_id, 'WM_CLASS'],
            capture_output=True, text=True, timeout=2
        )
        wm_class = ""
        if result.returncode == 0:
            # Parse: WM_CLASS(STRING) = "discord", "discord"
            match = re.search(r'"([^"]+)"', result.stdout)
            if match:
                wm_class = match.group(1)

        return WindowInfo(
            window_id=window_id,
            pid=pid,
            wm_class=wm_class,
            title=title
        )
    except Exception as e:
        print(f"Error getting window info: {e}", file=sys.stderr)
        return None


def detect_screen_type(window: WindowInfo) -> Tuple[str, ScreenType]:
    """Detect app and screen type from window info"""
    wm_class_lower = window.wm_class.lower()
    title = window.title

    # Check always-allowed apps
    for allowed in ALLOWED_APPS:
        if allowed.lower() in wm_class_lower:
            return allowed, ScreenType.ALLOWED

    # Check always-blocked apps
    for blocked in BLOCKED_APPS:
        if blocked.lower() in wm_class_lower:
            return blocked, ScreenType.FEED

    # Check known apps with DM detection
    for app_name, patterns in APP_PATTERNS.items():
        # Check if WM_CLASS matches
        if not any(wc.lower() in wm_class_lower for wc in patterns['wm_class']):
            continue

        # Check DM patterns first (higher priority)
        for pattern in patterns.get('dm_patterns', []):
            if re.search(pattern, title, re.IGNORECASE):
                return app_name, ScreenType.DM

        # Check server/feed patterns
        for pattern in patterns.get('server_patterns', []):
            if re.search(pattern, title, re.IGNORECASE):
                return app_name, ScreenType.SERVER_CHANNEL

        # App matched but no specific pattern - default to unknown
        return app_name, ScreenType.UNKNOWN

    # Unknown app - allow
    return "unknown", ScreenType.ALLOWED


def check_block(window: WindowInfo) -> BlockDecision:
    """Check if current window should be blocked"""
    app_name, screen_type = detect_screen_type(window)

    if screen_type == ScreenType.ALLOWED:
        return BlockDecision(
            should_block=False,
            reason=f"{app_name} is allowed",
            app_name=app_name,
            screen_type=screen_type
        )

    if screen_type == ScreenType.DM or screen_type == ScreenType.DM_LIST:
        return BlockDecision(
            should_block=False,
            reason=f"{app_name} DMs are allowed",
            app_name=app_name,
            screen_type=screen_type
        )

    if screen_type == ScreenType.SERVER_CHANNEL:
        return BlockDecision(
            should_block=True,
            reason=f"{app_name} server channels are blocked. Use DMs instead.",
            app_name=app_name,
            screen_type=screen_type
        )

    if screen_type == ScreenType.FEED:
        return BlockDecision(
            should_block=True,
            reason=f"{app_name} is blocked. Focus on your goals.",
            app_name=app_name,
            screen_type=screen_type
        )

    # Unknown - block to be safe
    return BlockDecision(
        should_block=True,
        reason=f"{app_name} - unknown screen, blocked by default",
        app_name=app_name,
        screen_type=screen_type
    )


def show_notification(title: str, message: str, urgency: str = "critical"):
    """Show desktop notification"""
    try:
        subprocess.run([
            'notify-send',
            '-u', urgency,
            '-a', 'TotalControl',
            title,
            message
        ], timeout=5)
    except Exception as e:
        print(f"Error showing notification: {e}", file=sys.stderr)


def monitor_loop(interval: float = 1.0, verbose: bool = False):
    """Main monitoring loop"""
    print("TotalControl Desktop Monitor started")
    print("Monitoring window focus for DM/Feed detection...")
    print("Press Ctrl+C to stop\n")

    last_blocked_window = None
    last_decision = None

    while True:
        try:
            window = get_active_window()

            if window is None:
                time.sleep(interval)
                continue

            decision = check_block(window)

            # Only act on changes
            if window.window_id != last_blocked_window or \
               (last_decision and decision.should_block != last_decision.should_block):

                if verbose:
                    print(f"[{decision.app_name}] {window.title[:50]}")
                    print(f"  Screen: {decision.screen_type.value}")
                    print(f"  Blocked: {decision.should_block}")
                    if decision.should_block:
                        print(f"  Reason: {decision.reason}")
                    print()

                if decision.should_block:
                    show_notification(
                        "TotalControl - BLOCKED",
                        decision.reason
                    )
                    # Could also minimize window or show overlay
                    # subprocess.run(['xdotool', 'windowminimize', window.window_id])

                last_blocked_window = window.window_id
                last_decision = decision

            time.sleep(interval)

        except KeyboardInterrupt:
            print("\nMonitor stopped")
            break
        except Exception as e:
            print(f"Error in monitor loop: {e}", file=sys.stderr)
            time.sleep(interval)


def test_patterns():
    """Test window title patterns"""
    test_cases = [
        # Discord
        ("discord", "@JohnDoe - Discord", ScreenType.DM),
        ("discord", "Discord", ScreenType.DM),  # Home/DM list
        ("discord", "Friends - Discord", ScreenType.DM),
        ("discord", "#general - My Server - Discord", ScreenType.SERVER_CHANNEL),
        ("discord", "#voice-chat - Gaming - Discord", ScreenType.SERVER_CHANNEL),
        ("discord", "John and 2 others - Discord", ScreenType.DM),  # Group DM

        # Slack
        ("slack", "* John Doe | Slack", ScreenType.DM),
        ("slack", "#engineering | Company | Slack", ScreenType.SERVER_CHANNEL),

        # Always allowed
        ("spotify", "Spotify", ScreenType.ALLOWED),
        ("telegram-desktop", "Telegram", ScreenType.ALLOWED),
    ]

    print("Testing window title patterns:\n")
    passed = 0
    failed = 0

    for wm_class, title, expected in test_cases:
        window = WindowInfo(
            window_id="test",
            pid=0,
            wm_class=wm_class,
            title=title
        )
        app_name, screen_type = detect_screen_type(window)

        status = "PASS" if screen_type == expected else "FAIL"
        if status == "PASS":
            passed += 1
        else:
            failed += 1

        print(f"[{status}] {wm_class}: '{title}'")
        print(f"       Expected: {expected.value}, Got: {screen_type.value}")
        print()

    print(f"Results: {passed}/{passed+failed} passed")
    return failed == 0


if __name__ == "__main__":
    if "--test" in sys.argv:
        success = test_patterns()
        sys.exit(0 if success else 1)

    verbose = "-v" in sys.argv or "--verbose" in sys.argv
    monitor_loop(interval=0.5, verbose=verbose)
