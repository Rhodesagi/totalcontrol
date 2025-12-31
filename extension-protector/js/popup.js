// TotalControl Popup Script
// Supports: NO X UNTIL Y, NO X DURING Y, ALLOW X DURING Y

const RuleMode = {
  UNTIL: 'until',
  DURING: 'during',
  ALLOW_DURING: 'allowDuring'
};

const CATEGORIES = {
  'Social': ['facebook.com', 'instagram.com', 'twitter.com', 'x.com', 'tiktok.com', 'reddit.com'],
  'Streaming': ['netflix.com', 'youtube.com', 'hulu.com', 'twitch.tv', 'spotify.com'],
  'Messaging': ['whatsapp.com', 'discord.com', 'slack.com', 'telegram.org'],
  'Gaming': ['store.steampowered.com', 'epicgames.com', 'roblox.com'],
  'News': ['cnn.com', 'bbc.com', 'nytimes.com', 'reddit.com/r/news']
};

let rules = [];
let selectedCategories = new Set();
let selectedMode = RuleMode.UNTIL;

// Initialize
document.addEventListener('DOMContentLoaded', async () => {
  await loadRules();
  renderCategories();
  setupEventListeners();
});

async function loadRules() {
  const data = await chrome.storage.local.get(['rules', 'progress']);
  rules = data.rules || [];
  renderRules();
}

function renderRules() {
  const list = document.getElementById('rules-list');

  if (rules.length === 0) {
    list.innerHTML = '<div class="empty">No rules yet. Add one below.</div>';
    return;
  }

  list.innerHTML = rules.map((rule, i) => {
    const ruleItems = rule.items || rule.blockedItems || [];
    const items = ruleItems.slice(0, 2).join(', ');
    const more = ruleItems.length > 2 ? ` +${ruleItems.length - 2}` : '';
    const condition = formatCondition(rule.condition);
    const mode = rule.mode || RuleMode.UNTIL;

    const modeLabel = getModeLabel(mode);
    const modeColor = getModeColor(mode);
    const prefix = mode === RuleMode.ALLOW_DURING ? 'ALLOW' : 'NO';
    const keyword = mode === RuleMode.UNTIL ? 'UNTIL' : 'DURING';

    const exceptions = rule.exceptions || [];
    const exceptText = exceptions.length > 0
      ? `<br><span style="color: #44ff44">UNLESS ${exceptions.slice(0, 2).join(', ')}${exceptions.length > 2 ? ' +' + (exceptions.length - 2) : ''}</span>`
      : '';

    return `
      <div class="rule" data-index="${i}">
        <div class="rule-text">
          <span class="mode-badge" style="background: ${modeColor}20; color: ${modeColor}; border: 1px solid ${modeColor}; padding: 1px 4px; font-size: 9px; margin-right: 4px;">${modeLabel}</span><br>
          ${prefix} ${items}${more}<br>
          <span style="color: #ffb000">${keyword} ${condition}</span>${exceptText}
        </div>
        <button class="rule-delete" data-index="${i}">&times;</button>
      </div>
    `;
  }).join('');

  // Add delete handlers
  list.querySelectorAll('.rule-delete').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const index = parseInt(e.target.dataset.index);
      deleteRule(index);
    });
  });
}

function getModeLabel(mode) {
  switch (mode) {
    case RuleMode.UNTIL: return 'UNTIL';
    case RuleMode.DURING: return 'BLOCK DURING';
    case RuleMode.ALLOW_DURING: return 'ONLY DURING';
    default: return 'UNTIL';
  }
}

function getModeColor(mode) {
  switch (mode) {
    case RuleMode.UNTIL: return '#ffb000';
    case RuleMode.DURING: return '#ff4444';
    case RuleMode.ALLOW_DURING: return '#44ff44';
    default: return '#ffb000';
  }
}

function formatCondition(condition) {
  switch (condition.type) {
    case 'steps':
      return `${(condition.stepsTarget || condition.steps_target || 10000).toLocaleString()} steps`;
    case 'time':
      return condition.timeTarget || condition.time_target || '17:00';
    case 'timeRange':
      const tr = condition.timeRange || condition.time_range;
      if (tr) {
        return `${tr.startTime || tr.start || '09:00'} - ${tr.endTime || tr.end || '17:00'}`;
      }
      return 'time range';
    case 'workout':
      return `${condition.workoutMinutes || condition.workout_minutes || 30}min workout`;
    case 'schedule':
      if (condition.schedule && condition.schedule.days) {
        if (condition.schedule.days.length === 5) return 'weekdays';
        if (condition.schedule.days.length === 2) return 'weekends';
        return 'custom days';
      }
      return 'schedule';
    case 'location':
      return `at ${condition.location?.name || 'location'}`;
    case 'tomorrow':
      return 'tomorrow';
    case 'password':
      return 'password';
    default:
      return 'goal met';
  }
}

function renderCategories() {
  const container = document.getElementById('category-chips');
  container.innerHTML = Object.keys(CATEGORIES).map(cat =>
    `<button class="chip" data-category="${cat}">${cat}</button>`
  ).join('');

  container.querySelectorAll('.chip').forEach(chip => {
    chip.addEventListener('click', () => {
      const cat = chip.dataset.category;
      if (selectedCategories.has(cat)) {
        selectedCategories.delete(cat);
        chip.classList.remove('selected');
      } else {
        selectedCategories.add(cat);
        chip.classList.add('selected');
      }
      updateBlockInput();
    });
  });
}

function updateBlockInput() {
  const input = document.getElementById('block-input');
  const sites = [];
  selectedCategories.forEach(cat => {
    sites.push(...CATEGORIES[cat]);
  });
  input.value = [...new Set(sites)].join(', ');
}

function setupEventListeners() {
  const addBtn = document.getElementById('add-btn');
  const addForm = document.getElementById('add-form');
  const cancelBtn = document.getElementById('cancel-btn');
  const saveBtn = document.getElementById('save-btn');
  const conditionType = document.getElementById('condition-type');
  const valueRow = document.getElementById('value-row');
  const valueInput = document.getElementById('condition-value');
  const modeSelect = document.getElementById('rule-mode');
  const sitesLabel = document.getElementById('sites-label');
  const conditionLabel = document.getElementById('condition-label');

  addBtn.addEventListener('click', () => {
    addForm.classList.add('active');
    addBtn.style.display = 'none';
  });

  cancelBtn.addEventListener('click', () => {
    addForm.classList.remove('active');
    addBtn.style.display = 'block';
    resetForm();
  });

  // Handle mode change
  modeSelect.addEventListener('change', () => {
    const mode = modeSelect.value;
    if (mode === 'allowDuring') {
      sitesLabel.textContent = 'ALLOW (quick select):';
    } else {
      sitesLabel.textContent = 'BLOCK (quick select):';
    }
    conditionLabel.textContent = mode === 'until' ? 'UNTIL:' : 'DURING:';

    // Update condition type options based on mode
    updateConditionOptions(mode);
  });

  conditionType.addEventListener('change', () => {
    const type = conditionType.value;
    if (type === 'tomorrow') {
      valueRow.style.display = 'none';
    } else {
      valueRow.style.display = 'block';
      switch (type) {
        case 'steps': valueInput.placeholder = '10000'; break;
        case 'time': valueInput.placeholder = '17:00'; break;
        case 'timeRange': valueInput.placeholder = '09:00-17:00'; break;
        case 'workout': valueInput.placeholder = '30'; break;
        case 'schedule': valueInput.placeholder = 'weekdays'; break;
      }
    }
  });

  saveBtn.addEventListener('click', saveRule);
}

function updateConditionOptions(mode) {
  const conditionType = document.getElementById('condition-type');
  const current = conditionType.value;

  if (mode === 'until') {
    conditionType.innerHTML = `
      <option value="steps">Steps</option>
      <option value="time">Time</option>
      <option value="workout">Workout</option>
      <option value="tomorrow">Tomorrow</option>
    `;
    // Reset to steps if current is a DURING-only type
    if (['timeRange', 'schedule'].includes(current)) {
      conditionType.value = 'steps';
    }
  } else {
    conditionType.innerHTML = `
      <option value="timeRange">Time Range</option>
      <option value="workout">Workout</option>
      <option value="schedule">Days</option>
    `;
    // Reset to timeRange if current is an UNTIL-only type
    if (['steps', 'time', 'tomorrow'].includes(current)) {
      conditionType.value = 'timeRange';
      document.getElementById('condition-value').placeholder = '09:00-17:00';
    }
  }
}

async function saveRule() {
  const blockInput = document.getElementById('block-input');
  const conditionType = document.getElementById('condition-type');
  const valueInput = document.getElementById('condition-value');
  const modeSelect = document.getElementById('rule-mode');
  const exceptionsInput = document.getElementById('exceptions-input');

  const items = blockInput.value.split(',').map(s => s.trim()).filter(s => s);
  if (items.length === 0) {
    alert('Enter at least one site');
    return;
  }

  const mode = modeSelect ? modeSelect.value : RuleMode.UNTIL;
  const exceptions = exceptionsInput.value.split(',').map(s => s.trim()).filter(s => s);
  const condition = { type: conditionType.value };
  const value = valueInput.value.trim();

  switch (condition.type) {
    case 'steps':
      condition.stepsTarget = parseInt(value) || 10000;
      break;
    case 'time':
      condition.timeTarget = value || '17:00';
      break;
    case 'timeRange':
      // Parse time range (e.g., "09:00-17:00" or "09:00 - 17:00")
      const parts = value.split(/\s*[-–]\s*/);
      condition.timeRange = {
        startTime: parts[0] || '09:00',
        endTime: parts[1] || '17:00'
      };
      break;
    case 'workout':
      condition.workoutMinutes = parseInt(value) || 30;
      break;
    case 'schedule':
      condition.schedule = {
        days: value === 'weekends' ? [6, 7] : [1, 2, 3, 4, 5]
      };
      break;
  }

  const rule = {
    id: Date.now().toString(),
    items,
    mode,
    condition,
    exceptions,
    enabled: true,
    createdAt: new Date().toISOString()
  };

  rules.push(rule);
  await chrome.storage.local.set({ rules });

  document.getElementById('add-form').classList.remove('active');
  document.getElementById('add-btn').style.display = 'block';
  resetForm();
  renderRules();
}

async function deleteRule(index) {
  rules.splice(index, 1);
  await chrome.storage.local.set({ rules });
  renderRules();
}

function resetForm() {
  document.getElementById('block-input').value = '';
  document.getElementById('rule-mode').value = 'until';
  document.getElementById('condition-type').value = 'steps';
  document.getElementById('condition-value').value = '';
  document.getElementById('exceptions-input').value = '';
  document.getElementById('value-row').style.display = 'block';
  document.getElementById('sites-label').textContent = 'BLOCK (quick select):';
  document.getElementById('condition-label').textContent = 'UNTIL:';
  updateConditionOptions('until');
  selectedCategories.clear();
  document.querySelectorAll('.chip').forEach(c => c.classList.remove('selected'));
}
