#!/usr/bin/env python3
"""
TotalControl Extension Watchdog

Monitors the browser extension heartbeat and alerts if it goes silent.
Each component watches the other:
- Extension sends heartbeat to storage/native messaging
- Desktop app monitors heartbeat, alerts if extension disabled/uninstalled
- Desktop app has its own heartbeat that extension could monitor

Usage:
    python extension_watchdog.py [--daemon]
"""

import json
import os
import sys
import time
import subprocess
from pathlib import Path
from datetime import datetime

# Chrome storage location (varies by platform)
CHROME_STORAGE_PATHS = [
    # Linux
    Path.home() / ".config/google-chrome/Default/Local Extension Settings",
    Path.home() / ".config/chromium/Default/Local Extension Settings",
    # macOS
    Path.home() / "Library/Application Support/Google/Chrome/Default/Local Extension Settings",
    # Windows (run from WSL or adapt path)
]

# Extension ID (update after installing)
EXTENSION_ID = ""  # Will be auto-detected or set manually

# Heartbeat settings
HEARTBEAT_TIMEOUT = 30  # seconds - if no heartbeat for this long, assume dead
CHECK_INTERVAL = 5  # How often to check

# Desktop app heartbeat file (extension can monitor this)
DESKTOP_HEARTBEAT_FILE = Path.home() / ".totalcontrol" / "desktop_heartbeat.json"


def find_extension_storage():
    """Find Chrome extension local storage path"""
    for base_path in CHROME_STORAGE_PATHS:
        if base_path.exists():
            # Look for TotalControl extension folder
            for ext_dir in base_path.iterdir():
                if ext_dir.is_dir():
                    # Check if it's our extension (would need to verify)
                    return ext_dir
    return None


def get_extension_heartbeat_from_storage():
    """
    Read extension heartbeat from Chrome local storage.
    Note: Chrome's LevelDB storage is complex - this is simplified.
    In practice, use native messaging or a shared file.
    """
    # For now, check a shared file that extension writes to
    heartbeat_file = Path.home() / ".totalcontrol" / "extension_heartbeat.json"

    if not heartbeat_file.exists():
        return None

    try:
        with open(heartbeat_file, 'r') as f:
            data = json.load(f)
            return data.get('timestamp')
    except:
        return None


def write_desktop_heartbeat():
    """Write desktop app heartbeat for extension to monitor"""
    DESKTOP_HEARTBEAT_FILE.parent.mkdir(parents=True, exist_ok=True)

    data = {
        'timestamp': time.time(),
        'active': True,
        'pid': os.getpid()
    }

    with open(DESKTOP_HEARTBEAT_FILE, 'w') as f:
        json.dump(data, f)


def show_alert(title, message):
    """Show desktop notification"""
    try:
        subprocess.run([
            'notify-send',
            '-u', 'critical',
            '-a', 'TotalControl Watchdog',
            title,
            message
        ], timeout=5)
    except:
        print(f"ALERT: {title} - {message}")


def on_extension_dead():
    """Called when extension appears to be disabled/uninstalled"""
    show_alert(
        "⚠️ TotalControl Extension Disabled!",
        "The browser extension has stopped responding.\n"
        "It may have been disabled or uninstalled.\n"
        "Blocking will not work until it's restored."
    )

    # Log the event
    log_file = Path.home() / ".totalcontrol" / "watchdog_events.log"
    with open(log_file, 'a') as f:
        f.write(f"{datetime.now().isoformat()} - Extension went silent\n")

    # Could also:
    # - Open browser to reinstall extension
    # - Send email/SMS alert
    # - Block at system level (hosts file, firewall)
    # - Start more aggressive monitoring


def on_extension_restored():
    """Called when extension comes back online"""
    show_alert(
        "✓ TotalControl Extension Active",
        "The browser extension is working again."
    )

    log_file = Path.home() / ".totalcontrol" / "watchdog_events.log"
    with open(log_file, 'a') as f:
        f.write(f"{datetime.now().isoformat()} - Extension restored\n")


def monitor_loop():
    """Main monitoring loop"""
    print("TotalControl Extension Watchdog")
    print(f"Checking every {CHECK_INTERVAL}s, timeout {HEARTBEAT_TIMEOUT}s")
    print("-" * 50)

    extension_was_alive = True
    last_heartbeat = time.time()

    while True:
        try:
            # Write our own heartbeat
            write_desktop_heartbeat()

            # Check extension heartbeat
            ext_heartbeat = get_extension_heartbeat_from_storage()

            if ext_heartbeat:
                age = time.time() - ext_heartbeat

                if age < HEARTBEAT_TIMEOUT:
                    # Extension is alive
                    if not extension_was_alive:
                        on_extension_restored()
                        extension_was_alive = True

                    last_heartbeat = ext_heartbeat
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Extension alive (heartbeat {age:.1f}s ago)")
                else:
                    # Heartbeat is stale
                    if extension_was_alive:
                        on_extension_dead()
                        extension_was_alive = False
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Extension DEAD (last heartbeat {age:.1f}s ago)")
            else:
                # No heartbeat file at all
                if extension_was_alive:
                    # First time - might just not be set up yet
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] No heartbeat file - extension may not be configured")
                else:
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Still no heartbeat")

            time.sleep(CHECK_INTERVAL)

        except KeyboardInterrupt:
            print("\nWatchdog stopped")
            break
        except Exception as e:
            print(f"Error: {e}")
            time.sleep(CHECK_INTERVAL)


def setup_native_messaging_host():
    """
    Set up Chrome native messaging host for direct communication.
    This allows extension to send messages directly to desktop app.
    """
    manifest = {
        "name": "com.rhodesai.totalcontrol",
        "description": "TotalControl Desktop App",
        "path": str(Path(__file__).parent / "native_host.py"),
        "type": "stdio",
        "allowed_origins": [
            "chrome-extension://YOUR_EXTENSION_ID/"  # Update with actual ID
        ]
    }

    # Chrome native messaging host location
    nm_dir = Path.home() / ".config/google-chrome/NativeMessagingHosts"
    nm_dir.mkdir(parents=True, exist_ok=True)

    manifest_path = nm_dir / "com.rhodesai.totalcontrol.json"
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)

    print(f"Native messaging host installed at: {manifest_path}")
    print("Update 'allowed_origins' with your extension ID")


if __name__ == "__main__":
    if "--setup-native" in sys.argv:
        setup_native_messaging_host()
    elif "--daemon" in sys.argv:
        # Run in background
        if os.fork() == 0:
            monitor_loop()
    else:
        monitor_loop()
