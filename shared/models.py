"""
TotalControl - Shared Data Models
"NO X UNTIL X" rule-based blocking
"""
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional
from datetime import datetime, time
import json

class ConditionType(Enum):
    STEPS = "steps"           # NO X UNTIL 10,000 steps
    TIME = "time"             # NO X UNTIL 5:00 PM
    WORKOUT = "workout"       # NO X UNTIL 30min workout
    LOCATION = "location"     # NO X UNTIL at gym
    TOMORROW = "tomorrow"     # NO X UNTIL tomorrow
    PASSWORD = "password"     # NO X UNTIL password entered

@dataclass
class Location:
    name: str               # "Gym", "Office", etc.
    latitude: float
    longitude: float
    radius_meters: int = 100  # Geofence radius

@dataclass
class Condition:
    type: ConditionType
    # Type-specific values
    steps_target: Optional[int] = None
    time_target: Optional[str] = None  # "17:00" format
    workout_minutes: Optional[int] = None
    location: Optional[Location] = None

    def to_dict(self) -> dict:
        d = {"type": self.type.value}
        if self.steps_target: d["steps_target"] = self.steps_target
        if self.time_target: d["time_target"] = self.time_target
        if self.workout_minutes: d["workout_minutes"] = self.workout_minutes
        if self.location: d["location"] = {
            "name": self.location.name,
            "lat": self.location.latitude,
            "lng": self.location.longitude,
            "radius": self.location.radius_meters
        }
        return d

    @staticmethod
    def from_dict(d: dict) -> 'Condition':
        c = Condition(type=ConditionType(d["type"]))
        c.steps_target = d.get("steps_target")
        c.time_target = d.get("time_target")
        c.workout_minutes = d.get("workout_minutes")
        if loc := d.get("location"):
            c.location = Location(loc["name"], loc["lat"], loc["lng"], loc.get("radius", 100))
        return c

    def describe(self) -> str:
        """Human-readable description"""
        if self.type == ConditionType.STEPS:
            return f"{self.steps_target:,} steps"
        elif self.type == ConditionType.TIME:
            return self.time_target
        elif self.type == ConditionType.WORKOUT:
            return f"{self.workout_minutes}min workout"
        elif self.type == ConditionType.LOCATION:
            return f"at {self.location.name}"
        elif self.type == ConditionType.TOMORROW:
            return "tomorrow"
        elif self.type == ConditionType.PASSWORD:
            return "password"
        return "unknown"

@dataclass
class Rule:
    id: str
    blocked_items: List[str]  # ["Netflix", "YouTube", "netflix.com"]
    condition: Condition
    enabled: bool = True
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "blocked_items": self.blocked_items,
            "condition": self.condition.to_dict(),
            "enabled": self.enabled,
            "created_at": self.created_at
        }

    @staticmethod
    def from_dict(d: dict) -> 'Rule':
        return Rule(
            id=d["id"],
            blocked_items=d["blocked_items"],
            condition=Condition.from_dict(d["condition"]),
            enabled=d.get("enabled", True),
            created_at=d.get("created_at", datetime.now().isoformat())
        )

    def describe(self) -> str:
        """NO X UNTIL Y format"""
        items = ", ".join(self.blocked_items[:3])
        if len(self.blocked_items) > 3:
            items += f" +{len(self.blocked_items)-3}"
        return f"NO {items} UNTIL {self.condition.describe()}"

@dataclass
class Progress:
    """Current progress toward conditions"""
    steps_today: int = 0
    workout_minutes_today: int = 0
    current_location: Optional[Location] = None

    def check_condition(self, condition: Condition) -> tuple[bool, str]:
        """Returns (is_met, progress_string)"""
        if condition.type == ConditionType.STEPS:
            met = self.steps_today >= condition.steps_target
            pct = min(100, int(self.steps_today / condition.steps_target * 100))
            return met, f"{self.steps_today:,}/{condition.steps_target:,} ({pct}%)"

        elif condition.type == ConditionType.TIME:
            target = datetime.strptime(condition.time_target, "%H:%M").time()
            now = datetime.now().time()
            met = now >= target
            if met:
                return True, "Time reached"
            else:
                # Calculate time remaining
                target_dt = datetime.combine(datetime.today(), target)
                now_dt = datetime.now()
                remaining = target_dt - now_dt
                mins = int(remaining.total_seconds() / 60)
                if mins > 60:
                    return False, f"{mins//60}h {mins%60}m left"
                return False, f"{mins}m left"

        elif condition.type == ConditionType.WORKOUT:
            met = self.workout_minutes_today >= condition.workout_minutes
            return met, f"{self.workout_minutes_today}/{condition.workout_minutes}min"

        elif condition.type == ConditionType.LOCATION:
            if not self.current_location:
                return False, "Location unknown"
            # Simple distance check (haversine would be better)
            from math import sqrt
            dist = sqrt(
                (self.current_location.latitude - condition.location.latitude)**2 +
                (self.current_location.longitude - condition.location.longitude)**2
            ) * 111000  # rough meters
            met = dist <= condition.location.radius_meters
            return met, f"{'At' if met else 'Not at'} {condition.location.name}"

        elif condition.type == ConditionType.TOMORROW:
            # Never met until date changes
            return False, "Blocked until tomorrow"

        elif condition.type == ConditionType.PASSWORD:
            return False, "Enter password to unlock"

        return False, "Unknown"

class RuleStore:
    """Persist rules to JSON file"""
    def __init__(self, filepath: str):
        self.filepath = filepath
        self.rules: List[Rule] = []
        self.load()

    def load(self):
        try:
            with open(self.filepath, 'r') as f:
                data = json.load(f)
                self.rules = [Rule.from_dict(r) for r in data.get("rules", [])]
        except FileNotFoundError:
            self.rules = []

    def save(self):
        with open(self.filepath, 'w') as f:
            json.dump({"rules": [r.to_dict() for r in self.rules]}, f, indent=2)

    def add(self, rule: Rule):
        self.rules.append(rule)
        self.save()

    def remove(self, rule_id: str):
        self.rules = [r for r in self.rules if r.id != rule_id]
        self.save()

    def get_blocked_items(self, progress: Progress) -> List[str]:
        """Get all currently blocked items based on progress"""
        blocked = []
        for rule in self.rules:
            if not rule.enabled:
                continue
            met, _ = progress.check_condition(rule.condition)
            if not met:
                blocked.extend(rule.blocked_items)
        return list(set(blocked))
