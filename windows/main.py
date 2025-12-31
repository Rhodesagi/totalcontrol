"""
TotalControl - Windows App
"NO X UNTIL X" rule-based blocking

Cold War aesthetic, simple rule list UI
"""
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
import sys
import os
import uuid
from datetime import datetime
import threading
import time

# Add shared models
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'shared'))
from models import Rule, Condition, ConditionType, Location, Progress, RuleStore

# Local modules
from blocker import get_blocker
from fitness_sync import get_fitness_sync

# ═══════════════════════════════════════════════════════════════
# COLD WAR THEME COLORS
# ═══════════════════════════════════════════════════════════════
COLORS = {
    'bg': '#1a1a0f',
    'panel': '#2a2a1f',
    'metal': '#3d3d2d',
    'amber': '#ffb000',
    'amber_dim': '#8b6914',
    'green': '#00ff00',
    'green_dim': '#006600',
    'red': '#ff3333',
    'red_dim': '#661414',
    'text': '#d4c4a0',
    'text_dim': '#6b6348',
}

class TotalControlApp:
    def __init__(self, root):
        self.root = root
        self.root.title("◆ TOTAL CONTROL ◆")
        self.root.geometry("500x700")
        self.root.configure(bg=COLORS['bg'])
        self.root.resizable(False, False)

        # Data
        self.store = RuleStore(os.path.expanduser("~/totalcontrol_rules.json"))
        self.progress = Progress()
        self.blocker = get_blocker()
        self.fitness = get_fitness_sync()

        # Connect fitness updates
        self.fitness.add_callback(self.on_fitness_update)
        self.fitness.start_sync_loop(interval_seconds=60)

        self.setup_ui()
        self.refresh_rules()

        # Start blocker
        self.blocker.start_monitoring()
        self.update_blocking()

    def setup_ui(self):
        # Header
        header = tk.Frame(self.root, bg=COLORS['metal'], height=60)
        header.pack(fill='x', padx=10, pady=10)
        header.pack_propagate(False)

        tk.Label(header, text="◆ TOTAL CONTROL ◆",
                font=("Courier New", 18, "bold"),
                fg=COLORS['amber'], bg=COLORS['metal']).pack(pady=15)

        # Subtitle
        tk.Label(self.root, text="NO X UNTIL X",
                font=("Courier New", 10),
                fg=COLORS['text_dim'], bg=COLORS['bg']).pack()

        # Rules list frame
        self.rules_frame = tk.Frame(self.root, bg=COLORS['panel'])
        self.rules_frame.pack(fill='both', expand=True, padx=10, pady=10)

        # Add rule button
        add_btn = tk.Button(self.root, text="+ ADD RULE",
                           font=("Courier New", 12, "bold"),
                           fg=COLORS['bg'], bg=COLORS['amber'],
                           activebackground=COLORS['amber_dim'],
                           command=self.add_rule_dialog)
        add_btn.pack(pady=10)

        # Status bar
        self.status_var = tk.StringVar(value="PROTECTION ACTIVE")
        status = tk.Label(self.root, textvariable=self.status_var,
                         font=("Courier New", 9),
                         fg=COLORS['green'], bg=COLORS['bg'])
        status.pack(pady=5)

    def refresh_rules(self):
        # Clear existing
        for widget in self.rules_frame.winfo_children():
            widget.destroy()

        if not self.store.rules:
            tk.Label(self.rules_frame,
                    text="No rules yet.\nTap + ADD RULE to create one.",
                    font=("Courier New", 11),
                    fg=COLORS['text_dim'], bg=COLORS['panel'],
                    justify='center').pack(pady=50)
            return

        # Show each rule
        for rule in self.store.rules:
            self.create_rule_widget(rule)

    def create_rule_widget(self, rule: Rule):
        frame = tk.Frame(self.rules_frame, bg=COLORS['metal'], height=80)
        frame.pack(fill='x', padx=5, pady=5)
        frame.pack_propagate(False)

        # Check condition
        met, progress_str = self.progress.check_condition(rule.condition)

        # Status indicator
        status_color = COLORS['green'] if met else COLORS['red']
        status_text = "✓ ALLOWED" if met else "🔒 BLOCKED"

        # Left side - status
        left = tk.Frame(frame, bg=COLORS['metal'], width=100)
        left.pack(side='left', fill='y')
        left.pack_propagate(False)

        tk.Label(left, text=status_text,
                font=("Courier New", 9, "bold"),
                fg=status_color, bg=COLORS['metal']).pack(pady=10)

        # Center - rule info
        center = tk.Frame(frame, bg=COLORS['metal'])
        center.pack(side='left', fill='both', expand=True, padx=10)

        # Items blocked
        items_text = ", ".join(rule.blocked_items[:3])
        if len(rule.blocked_items) > 3:
            items_text += f" +{len(rule.blocked_items)-3}"

        tk.Label(center, text=f"NO {items_text}",
                font=("Courier New", 11, "bold"),
                fg=COLORS['text'], bg=COLORS['metal'],
                anchor='w').pack(fill='x', pady=(10,0))

        tk.Label(center, text=f"UNTIL {rule.condition.describe()}",
                font=("Courier New", 10),
                fg=COLORS['amber'], bg=COLORS['metal'],
                anchor='w').pack(fill='x')

        tk.Label(center, text=progress_str,
                font=("Courier New", 9),
                fg=COLORS['text_dim'], bg=COLORS['metal'],
                anchor='w').pack(fill='x')

        # Right side - delete button
        right = tk.Frame(frame, bg=COLORS['metal'], width=40)
        right.pack(side='right', fill='y')
        right.pack_propagate(False)

        del_btn = tk.Button(right, text="×",
                           font=("Courier New", 14, "bold"),
                           fg=COLORS['red'], bg=COLORS['metal'],
                           activebackground=COLORS['red_dim'],
                           bd=0, command=lambda: self.delete_rule(rule.id))
        del_btn.pack(pady=20)

    def add_rule_dialog(self):
        dialog = tk.Toplevel(self.root)
        dialog.title("NEW RULE")
        dialog.geometry("400x500")
        dialog.configure(bg=COLORS['panel'])
        dialog.transient(self.root)
        dialog.grab_set()

        # NO ___
        tk.Label(dialog, text="NO", font=("Courier New", 14, "bold"),
                fg=COLORS['amber'], bg=COLORS['panel']).pack(pady=(20,5))

        items_var = tk.StringVar()
        items_entry = tk.Entry(dialog, textvariable=items_var,
                              font=("Courier New", 12),
                              bg=COLORS['bg'], fg=COLORS['text'],
                              insertbackground=COLORS['amber'], width=30)
        items_entry.pack(pady=5)
        tk.Label(dialog, text="(comma-separated: Netflix, YouTube)",
                font=("Courier New", 8), fg=COLORS['text_dim'],
                bg=COLORS['panel']).pack()

        # UNTIL ___
        tk.Label(dialog, text="UNTIL", font=("Courier New", 14, "bold"),
                fg=COLORS['amber'], bg=COLORS['panel']).pack(pady=(20,5))

        condition_type = tk.StringVar(value="steps")

        conditions_frame = tk.Frame(dialog, bg=COLORS['panel'])
        conditions_frame.pack(pady=10)

        conditions = [
            ("steps", "Steps"),
            ("time", "Time"),
            ("workout", "Workout"),
            ("location", "Location"),
            ("tomorrow", "Tomorrow"),
            ("password", "Password"),
        ]

        for val, label in conditions:
            tk.Radiobutton(conditions_frame, text=label,
                          variable=condition_type, value=val,
                          font=("Courier New", 10),
                          fg=COLORS['text'], bg=COLORS['panel'],
                          selectcolor=COLORS['metal'],
                          activebackground=COLORS['panel']).pack(anchor='w')

        # Condition value
        tk.Label(dialog, text="VALUE", font=("Courier New", 12, "bold"),
                fg=COLORS['amber'], bg=COLORS['panel']).pack(pady=(20,5))

        value_var = tk.StringVar(value="10000")
        value_entry = tk.Entry(dialog, textvariable=value_var,
                              font=("Courier New", 12),
                              bg=COLORS['bg'], fg=COLORS['text'],
                              insertbackground=COLORS['amber'], width=20)
        value_entry.pack(pady=5)
        tk.Label(dialog, text="Steps: 10000 | Time: 17:00 | Workout: 30",
                font=("Courier New", 8), fg=COLORS['text_dim'],
                bg=COLORS['panel']).pack()

        def create():
            items = [i.strip() for i in items_var.get().split(',') if i.strip()]
            if not items:
                messagebox.showerror("Error", "Enter at least one item to block")
                return

            ctype = ConditionType(condition_type.get())
            condition = Condition(type=ctype)
            value = value_var.get().strip()

            try:
                if ctype == ConditionType.STEPS:
                    condition.steps_target = int(value)
                elif ctype == ConditionType.TIME:
                    condition.time_target = value  # "17:00"
                elif ctype == ConditionType.WORKOUT:
                    condition.workout_minutes = int(value)
                elif ctype == ConditionType.LOCATION:
                    # For now, just store name - would need lat/lng picker
                    condition.location = Location(value, 0, 0)
            except ValueError:
                messagebox.showerror("Error", "Invalid value")
                return

            rule = Rule(
                id=str(uuid.uuid4())[:8],
                blocked_items=items,
                condition=condition
            )
            self.store.add(rule)
            dialog.destroy()
            self.refresh_rules()

        tk.Button(dialog, text="CREATE RULE",
                 font=("Courier New", 12, "bold"),
                 fg=COLORS['bg'], bg=COLORS['amber'],
                 command=create).pack(pady=30)

    def delete_rule(self, rule_id: str):
        if messagebox.askyesno("Delete Rule", "Remove this rule?"):
            self.store.remove(rule_id)
            self.refresh_rules()

    def on_fitness_update(self, steps: int, workout_mins: int):
        """Called when fitness data updates"""
        self.progress.steps_today = steps
        self.progress.workout_minutes_today = workout_mins
        self.root.after(0, self.refresh_rules)
        self.root.after(0, self.update_blocking)

    def update_blocking(self):
        """Update what's blocked based on current progress"""
        blocked = self.store.get_blocked_items(self.progress)
        self.blocker.update_blocked(blocked)

        # Update status
        if blocked:
            self.status_var.set(f"BLOCKING {len(blocked)} ITEMS")
        else:
            self.status_var.set("ALL CONDITIONS MET")

    def get_blocked_items(self) -> list:
        """Get all currently blocked items"""
        return self.store.get_blocked_items(self.progress)


def main():
    root = tk.Tk()
    app = TotalControlApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
