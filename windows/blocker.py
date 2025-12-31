"""
TotalControl - Windows Blocking Engine

Blocks sites/apps via:
1. Hosts file (DNS blocking)
2. Process killing (app blocking)
3. Browser URL detection (via Chrome extension or accessibility)
"""
import os
import subprocess
import re
from typing import List, Set
import time
import threading

# Known site -> domain mappings
SITE_DOMAINS = {
    "netflix": ["netflix.com", "nflxvideo.net", "nflximg.net", "nflxso.net"],
    "youtube": ["youtube.com", "youtu.be", "googlevideo.com", "ytimg.com"],
    "tiktok": ["tiktok.com", "tiktokcdn.com", "tiktokv.com"],
    "reddit": ["reddit.com", "redd.it", "redditmedia.com"],
    "twitter": ["twitter.com", "x.com", "twimg.com"],
    "instagram": ["instagram.com", "cdninstagram.com"],
    "facebook": ["facebook.com", "fb.com", "fbcdn.net"],
    "twitch": ["twitch.tv", "twitchcdn.net"],
    "disney+": ["disneyplus.com", "disney-plus.net"],
    "hulu": ["hulu.com", "huluim.com"],
    "hbo": ["hbomax.com", "max.com"],
    "amazon": ["primevideo.com", "aiv-cdn.net"],
}

# Known app -> process names
APP_PROCESSES = {
    "netflix": ["Netflix.exe"],
    "spotify": ["Spotify.exe"],
    "discord": ["Discord.exe"],
    "steam": ["Steam.exe", "steamwebhelper.exe"],
    "epic": ["EpicGamesLauncher.exe"],
}

HOSTS_FILE = r"C:\Windows\System32\drivers\etc\hosts"
MARKER_START = "# === TOTALCONTROL START ==="
MARKER_END = "# === TOTALCONTROL END ==="


class WindowsBlocker:
    def __init__(self):
        self.blocked_items: Set[str] = set()
        self.running = False
        self._thread = None

    def update_blocked(self, items: List[str]):
        """Update the list of blocked items"""
        new_blocked = set(i.lower() for i in items)
        if new_blocked != self.blocked_items:
            self.blocked_items = new_blocked
            self._apply_hosts_block()

    def _get_domains_for_item(self, item: str) -> List[str]:
        """Get domains to block for a given item"""
        item_lower = item.lower()

        # Check if it's a known site
        if item_lower in SITE_DOMAINS:
            return SITE_DOMAINS[item_lower]

        # Check if item is already a domain
        if '.' in item:
            return [item_lower]

        # Try adding .com
        return [f"{item_lower}.com"]

    def _apply_hosts_block(self):
        """Update hosts file with blocked domains"""
        try:
            # Read current hosts
            with open(HOSTS_FILE, 'r') as f:
                content = f.read()

            # Remove old TotalControl entries
            pattern = f"{re.escape(MARKER_START)}.*?{re.escape(MARKER_END)}"
            content = re.sub(pattern, '', content, flags=re.DOTALL)
            content = content.strip()

            # Build new block list
            if self.blocked_items:
                block_lines = [MARKER_START]
                for item in self.blocked_items:
                    for domain in self._get_domains_for_item(item):
                        block_lines.append(f"127.0.0.1 {domain}")
                        block_lines.append(f"127.0.0.1 www.{domain}")
                block_lines.append(MARKER_END)

                content = content + "\n\n" + "\n".join(block_lines)

            # Write back
            with open(HOSTS_FILE, 'w') as f:
                f.write(content)

            # Flush DNS cache
            subprocess.run(["ipconfig", "/flushdns"],
                          capture_output=True, shell=True)

        except PermissionError:
            print("[Blocker] Need admin rights for hosts file")
        except Exception as e:
            print(f"[Blocker] Hosts error: {e}")

    def _kill_blocked_processes(self):
        """Kill processes for blocked apps"""
        for item in self.blocked_items:
            item_lower = item.lower()
            if item_lower in APP_PROCESSES:
                for proc_name in APP_PROCESSES[item_lower]:
                    try:
                        subprocess.run(
                            ["taskkill", "/F", "/IM", proc_name],
                            capture_output=True, shell=True
                        )
                    except:
                        pass

    def start_monitoring(self):
        """Start background process monitoring"""
        if self.running:
            return

        self.running = True
        def monitor():
            while self.running:
                self._kill_blocked_processes()
                time.sleep(5)

        self._thread = threading.Thread(target=monitor, daemon=True)
        self._thread.start()

    def stop_monitoring(self):
        """Stop monitoring"""
        self.running = False

    def clear_blocks(self):
        """Remove all blocks"""
        self.blocked_items = set()
        self._apply_hosts_block()


# Singleton instance
_blocker = None

def get_blocker() -> WindowsBlocker:
    global _blocker
    if _blocker is None:
        _blocker = WindowsBlocker()
    return _blocker
