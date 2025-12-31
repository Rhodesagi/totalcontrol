#!/usr/bin/env python3
"""
TotalControl Screen Analyzer

OCR screenshots to text, store results, classify DM vs Feed.
Builds dataset over time for pattern learning.

Usage:
    python screen_analyzer.py screenshot.png
    python screen_analyzer.py --monitor  # Continuous monitoring
    python screen_analyzer.py --learn    # Show learned patterns
"""

import subprocess
import json
import os
import sys
import time
import hashlib
import re
from datetime import datetime
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import Optional, List, Dict
from enum import Enum

# Data storage
DATA_DIR = Path.home() / ".totalcontrol"
SCREENS_DB = DATA_DIR / "screens.jsonl"
PATTERNS_FILE = DATA_DIR / "learned_patterns.json"

class ScreenType(Enum):
    DM = "dm"
    FEED = "feed"
    REELS = "reels"
    NOTIFICATIONS = "notifications"
    PROFILE = "profile"
    SEARCH = "search"
    SETTINGS = "settings"
    UNKNOWN = "unknown"

@dataclass
class ScreenAnalysis:
    timestamp: str
    app_hint: str  # From window title, process name, or user input
    screen_type: ScreenType
    confidence: float
    raw_text: str
    text_hash: str
    matched_patterns: List[str]
    should_block: bool
    screenshot_path: Optional[str] = None

# ============ PATTERN DATABASE ============
# These patterns detect screen types from OCR text

PATTERNS = {
    # ----- DM INDICATORS (ALLOW) -----
    "dm": {
        "strong": [  # High confidence
            r"direct\s*messages?",
            r"new\s*message",
            r"send\s*a?\s*message",
            r"message\s*requests?",
            r"start\s*a?\s*(new\s*)?conversation",
            r"type\s*a\s*message",
            r"@\w+\s+online",  # Discord DM header
            r"friends?\s*(online|\d+)",
            r"write\s*a\s*message",
            r"chat\s*with",
        ],
        "medium": [  # Need additional context
            r"inbox",
            r"chats?",
            r"conversations?",
            r"reply",
            r"delivered",
            r"seen\s+\d",
            r"typing\.\.\.",
        ],
    },

    # ----- FEED INDICATORS (BLOCK) -----
    "feed": {
        "strong": [
            r"for\s*you",
            r"following\s*tab",
            r"suggested\s*(for\s*you|posts?)",
            r"sponsored",
            r"promoted",
            r"trending\s*(now|topics?)?",
            r"what.?s\s*happening",
            r"discover\s*more",
            r"explore\s*page",
            r"popular\s*(posts?|now)?",
            r"top\s*posts?",
            r"new\s*posts?",
            r"\d+\s*(likes?|comments?|shares?|retweets?)",
            r"liked\s*by\s*\d+",
            r"view\s*all\s*\d+\s*comments?",
        ],
        "medium": [
            r"home",
            r"feed",
            r"timeline",
            r"posts?",
            r"stories",
            r"follow\s*(back)?",
            r"share",
        ],
    },

    # ----- REELS/SHORTS (BLOCK) -----
    "reels": {
        "strong": [
            r"reels?",
            r"shorts?",
            r"tiktok",
            r"watch\s*now",
            r"swipe\s*up",
            r"original\s*audio",
            r"trending\s*audio",
            r"use\s*this\s*(sound|audio)",
        ],
    },

    # ----- NOTIFICATIONS (ALLOW) -----
    "notifications": {
        "strong": [
            r"notifications?",
            r"activity",
            r"all\s*notifications?",
            r"mentions?",
            r"replied\s*to\s*you",
            r"mentioned\s*you",
            r"tagged\s*you",
        ],
    },

    # ----- PROFILE (BLOCK) -----
    "profile": {
        "strong": [
            r"(\d+[km]?\s*)?(followers?|following)",
            r"edit\s*profile",
            r"bio",
            r"joined\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)",
            r"\d+\s*posts?\s+\d+\s*followers?",
        ],
    },

    # ----- SEARCH (BLOCK) -----
    "search": {
        "strong": [
            r"search\s*(twitter|x|instagram|facebook|reddit)",
            r"search\s*results?",
            r"try\s*searching",
            r"recent\s*searches?",
        ],
    },

    # ----- SETTINGS (ALLOW) -----
    "settings": {
        "strong": [
            r"settings?\s*(and|&)?\s*privacy",
            r"account\s*settings?",
            r"privacy\s*settings?",
            r"notification\s*settings?",
            r"security",
            r"password",
            r"two.?factor",
            r"log\s*out",
        ],
    },
}

# App-specific patterns (boost confidence when app is known)
APP_SPECIFIC = {
    "discord": {
        "dm": [r"#\s*friends", r"@me", r"direct\s*messages"],
        "feed": [r"#[a-z-]+", r"text\s*channels?", r"voice\s*channels?", r"server\s*settings"],
    },
    "twitter": {
        "dm": [r"messages?", r"new\s*message"],
        "feed": [r"for\s*you", r"following", r"what.?s\s*happening", r"trending"],
    },
    "instagram": {
        "dm": [r"messages?", r"send\s*message", r"primary", r"general"],
        "feed": [r"liked\s*by", r"suggested\s*for\s*you", r"reels?", r"explore"],
    },
    "reddit": {
        "dm": [r"chat", r"inbox", r"messages?"],
        "feed": [r"r/\w+", r"popular", r"upvote", r"downvote", r"karma"],
    },
    "facebook": {
        "dm": [r"messenger", r"new\s*message", r"chats?"],
        "feed": [r"news\s*feed", r"stories", r"reels?", r"marketplace"],
    },
    "linkedin": {
        "dm": [r"messaging", r"inmail"],
        "feed": [r"feed", r"connections?", r"jobs?"],
    },
}


def ensure_data_dir():
    """Create data directory if needed"""
    DATA_DIR.mkdir(parents=True, exist_ok=True)


def ocr_image(image_path: str) -> str:
    """Extract text from image using tesseract"""
    try:
        result = subprocess.run(
            ['tesseract', image_path, 'stdout', '-l', 'eng', '--psm', '3'],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            return result.stdout.strip()
        else:
            print(f"Tesseract error: {result.stderr}", file=sys.stderr)
            return ""
    except FileNotFoundError:
        print("Tesseract not installed. Run: sudo apt install tesseract-ocr", file=sys.stderr)
        return ""
    except Exception as e:
        print(f"OCR error: {e}", file=sys.stderr)
        return ""


def classify_text(text: str, app_hint: str = "") -> tuple[ScreenType, float, List[str]]:
    """
    Classify screen type from OCR text.
    Returns (screen_type, confidence, matched_patterns)
    """
    text_lower = text.lower()
    app_lower = app_hint.lower()

    scores = {st: 0.0 for st in ScreenType}
    matched = {st: [] for st in ScreenType}

    # Check general patterns
    for screen_type_str, pattern_groups in PATTERNS.items():
        try:
            screen_type = ScreenType(screen_type_str)
        except ValueError:
            continue

        for pattern in pattern_groups.get("strong", []):
            if re.search(pattern, text_lower, re.IGNORECASE):
                scores[screen_type] += 2.0
                matched[screen_type].append(f"strong:{pattern}")

        for pattern in pattern_groups.get("medium", []):
            if re.search(pattern, text_lower, re.IGNORECASE):
                scores[screen_type] += 0.5
                matched[screen_type].append(f"medium:{pattern}")

    # Boost with app-specific patterns
    for app_name, app_patterns in APP_SPECIFIC.items():
        if app_name in app_lower:
            for screen_type_str, patterns in app_patterns.items():
                try:
                    screen_type = ScreenType(screen_type_str)
                except ValueError:
                    continue
                for pattern in patterns:
                    if re.search(pattern, text_lower, re.IGNORECASE):
                        scores[screen_type] += 1.5  # App-specific boost
                        matched[screen_type].append(f"app:{app_name}:{pattern}")

    # Find best match
    best_type = max(scores, key=scores.get)
    best_score = scores[best_type]

    # Calculate confidence (0-1)
    total_score = sum(scores.values())
    confidence = best_score / total_score if total_score > 0 else 0

    # If no strong matches, return unknown
    if best_score < 1.0:
        return ScreenType.UNKNOWN, 0.0, []

    return best_type, min(confidence, 1.0), matched[best_type]


def should_block(screen_type: ScreenType) -> bool:
    """Determine if screen type should be blocked"""
    allowed = {
        ScreenType.DM,
        ScreenType.NOTIFICATIONS,
        ScreenType.SETTINGS,
    }
    return screen_type not in allowed


def analyze_screenshot(image_path: str, app_hint: str = "") -> ScreenAnalysis:
    """Full analysis pipeline: OCR → Classify → Store"""
    ensure_data_dir()

    # OCR
    raw_text = ocr_image(image_path)
    text_hash = hashlib.md5(raw_text.encode()).hexdigest()[:12]

    # Classify
    screen_type, confidence, matched_patterns = classify_text(raw_text, app_hint)

    # Create analysis
    analysis = ScreenAnalysis(
        timestamp=datetime.now().isoformat(),
        app_hint=app_hint,
        screen_type=screen_type,
        confidence=confidence,
        raw_text=raw_text[:2000],  # Truncate for storage
        text_hash=text_hash,
        matched_patterns=matched_patterns,
        should_block=should_block(screen_type),
        screenshot_path=image_path,
    )

    # Store for learning
    store_analysis(analysis)

    return analysis


def store_analysis(analysis: ScreenAnalysis):
    """Append analysis to JSONL database"""
    ensure_data_dir()
    with open(SCREENS_DB, 'a') as f:
        data = asdict(analysis)
        data['screen_type'] = analysis.screen_type.value
        f.write(json.dumps(data) + '\n')


def load_history(limit: int = 100) -> List[dict]:
    """Load recent analysis history"""
    if not SCREENS_DB.exists():
        return []

    with open(SCREENS_DB, 'r') as f:
        lines = f.readlines()[-limit:]

    return [json.loads(line) for line in lines if line.strip()]


def show_stats():
    """Show classification statistics"""
    history = load_history(1000)
    if not history:
        print("No history yet. Analyze some screenshots first.")
        return

    print(f"Total screens analyzed: {len(history)}")
    print()

    # Type distribution
    type_counts = {}
    for entry in history:
        st = entry.get('screen_type', 'unknown')
        type_counts[st] = type_counts.get(st, 0) + 1

    print("Screen type distribution:")
    for st, count in sorted(type_counts.items(), key=lambda x: -x[1]):
        blocked = "BLOCK" if should_block(ScreenType(st)) else "ALLOW"
        print(f"  {st:15} {count:4} ({blocked})")

    print()

    # App distribution
    app_counts = {}
    for entry in history:
        app = entry.get('app_hint', 'unknown') or 'unknown'
        app_counts[app] = app_counts.get(app, 0) + 1

    print("App distribution:")
    for app, count in sorted(app_counts.items(), key=lambda x: -x[1])[:10]:
        print(f"  {app:15} {count:4}")


def take_screenshot() -> str:
    """Take screenshot and return path"""
    ensure_data_dir()
    screenshot_dir = DATA_DIR / "screenshots"
    screenshot_dir.mkdir(exist_ok=True)

    filename = f"screen_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
    path = screenshot_dir / filename

    # Try different screenshot tools
    for cmd in [
        ['gnome-screenshot', '-f', str(path)],
        ['scrot', str(path)],
        ['import', '-window', 'root', str(path)],
        ['flameshot', 'full', '-p', str(screenshot_dir)],
    ]:
        try:
            result = subprocess.run(cmd, capture_output=True, timeout=10)
            if result.returncode == 0 and path.exists():
                return str(path)
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue

    raise RuntimeError("No screenshot tool available")


def get_active_app() -> str:
    """Get currently active app name"""
    try:
        result = subprocess.run(
            ['xdotool', 'getactivewindow', 'getwindowname'],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode == 0:
            title = result.stdout.strip()
            # Extract app hint from window title
            for app in ['Discord', 'Twitter', 'Instagram', 'Facebook', 'Reddit', 'Slack', 'LinkedIn']:
                if app.lower() in title.lower():
                    return app.lower()
            return title.split(' - ')[-1] if ' - ' in title else title
    except:
        pass
    return ""


def monitor_mode(interval: float = 2.0):
    """Continuous monitoring mode"""
    print("TotalControl Screen Monitor")
    print(f"Checking every {interval}s - Press Ctrl+C to stop")
    print("-" * 50)

    last_hash = None

    while True:
        try:
            # Take screenshot
            screenshot_path = take_screenshot()
            app_hint = get_active_app()

            # Analyze
            analysis = analyze_screenshot(screenshot_path, app_hint)

            # Only report if screen changed
            if analysis.text_hash != last_hash:
                last_hash = analysis.text_hash

                status = "BLOCKED" if analysis.should_block else "allowed"
                print(f"[{analysis.timestamp[11:19]}] {app_hint or 'unknown':12} "
                      f"{analysis.screen_type.value:12} ({analysis.confidence:.0%}) -> {status}")

                if analysis.matched_patterns:
                    print(f"           Patterns: {', '.join(analysis.matched_patterns[:3])}")

            # Cleanup old screenshots
            if not analysis.should_block:
                os.remove(screenshot_path)

            time.sleep(interval)

        except KeyboardInterrupt:
            print("\nMonitor stopped")
            break
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            time.sleep(interval)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return

    arg = sys.argv[1]

    if arg == "--monitor":
        interval = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0
        monitor_mode(interval)

    elif arg == "--stats":
        show_stats()

    elif arg == "--history":
        limit = int(sys.argv[2]) if len(sys.argv) > 2 else 20
        for entry in load_history(limit):
            print(f"{entry['timestamp'][:19]} | {entry.get('app_hint', ''):12} | "
                  f"{entry['screen_type']:12} | {'BLOCK' if entry['should_block'] else 'allow'}")

    elif arg == "--test":
        # Test with sample text
        test_texts = [
            ("Direct Messages - 3 unread", "discord"),
            ("For You - What's happening", "twitter"),
            ("liked by user123 and 45 others", "instagram"),
            ("Settings and Privacy", ""),
            ("#general - My Server - Discord", "discord"),
        ]
        for text, app in test_texts:
            st, conf, patterns = classify_text(text, app)
            blocked = "BLOCK" if should_block(st) else "allow"
            print(f"'{text[:40]}' -> {st.value} ({conf:.0%}) [{blocked}]")

    else:
        # Analyze single screenshot
        app_hint = sys.argv[2] if len(sys.argv) > 2 else get_active_app()
        analysis = analyze_screenshot(arg, app_hint)

        print(f"App:        {analysis.app_hint or 'unknown'}")
        print(f"Screen:     {analysis.screen_type.value}")
        print(f"Confidence: {analysis.confidence:.0%}")
        print(f"Decision:   {'BLOCKED' if analysis.should_block else 'ALLOWED'}")
        print(f"Patterns:   {', '.join(analysis.matched_patterns[:5])}")
        print(f"\nText preview:\n{analysis.raw_text[:500]}...")


if __name__ == "__main__":
    main()
