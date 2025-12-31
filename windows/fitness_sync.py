"""
TotalControl - Fitness Data Sync

Fetches fitness data from:
1. Google Fit API (if authorized)
2. Firebase (synced from phone)
3. Manual entry
"""
import os
import json
from datetime import datetime, date
from typing import Optional
import threading
import time

# Firebase config
FIREBASE_PROJECT = "totalcontrol-240ec"
FIREBASE_COLLECTION = "fitness_daily"
USER_ID = "rhodes"

# Local cache
CACHE_FILE = os.path.expanduser("~/totalcontrol_fitness.json")


class FitnessSync:
    def __init__(self):
        self.steps_today = 0
        self.workout_minutes_today = 0
        self.last_sync = None
        self._callbacks = []
        self._running = False
        self.load_cache()

    def load_cache(self):
        """Load cached fitness data"""
        try:
            with open(CACHE_FILE, 'r') as f:
                data = json.load(f)
                if data.get('date') == str(date.today()):
                    self.steps_today = data.get('steps', 0)
                    self.workout_minutes_today = data.get('workout_mins', 0)
                else:
                    # New day, reset
                    self.steps_today = 0
                    self.workout_minutes_today = 0
        except:
            pass

    def save_cache(self):
        """Save fitness data to cache"""
        try:
            with open(CACHE_FILE, 'w') as f:
                json.dump({
                    'date': str(date.today()),
                    'steps': self.steps_today,
                    'workout_mins': self.workout_minutes_today,
                    'last_sync': datetime.now().isoformat()
                }, f)
        except:
            pass

    def add_callback(self, callback):
        """Add callback to be called when fitness data updates"""
        self._callbacks.append(callback)

    def notify(self):
        """Notify all callbacks of update"""
        for cb in self._callbacks:
            try:
                cb(self.steps_today, self.workout_minutes_today)
            except:
                pass

    def fetch_from_firebase(self) -> bool:
        """Fetch today's fitness data from Firebase"""
        try:
            import requests
            today = str(date.today())
            doc_id = f"{USER_ID}_{today}"
            url = f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT}/databases/(default)/documents/{FIREBASE_COLLECTION}/{doc_id}"

            resp = requests.get(url, timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                fields = data.get('fields', {})

                self.steps_today = int(fields.get('steps', {}).get('integerValue', 0))
                self.workout_minutes_today = int(fields.get('workout_mins', {}).get('integerValue', 0))
                self.last_sync = datetime.now()
                self.save_cache()
                self.notify()
                return True
        except Exception as e:
            print(f"[FitnessSync] Firebase error: {e}")
        return False

    def manual_add_steps(self, steps: int):
        """Manually add steps"""
        self.steps_today += steps
        self.save_cache()
        self.notify()

    def manual_add_workout(self, minutes: int):
        """Manually add workout minutes"""
        self.workout_minutes_today += minutes
        self.save_cache()
        self.notify()

    def start_sync_loop(self, interval_seconds: int = 300):
        """Start background sync loop"""
        if self._running:
            return

        self._running = True
        def sync_loop():
            while self._running:
                self.fetch_from_firebase()
                time.sleep(interval_seconds)

        thread = threading.Thread(target=sync_loop, daemon=True)
        thread.start()

    def stop_sync(self):
        self._running = False


# Singleton
_sync = None

def get_fitness_sync() -> FitnessSync:
    global _sync
    if _sync is None:
        _sync = FitnessSync()
    return _sync
