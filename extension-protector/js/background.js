// TotalControl Background Service Worker
// Manages blocked sites and syncs with desktop app
// Supports: NO X UNTIL Y, NO X DURING Y, ALLOW X DURING Y

// Rule modes
const RuleMode = {
  UNTIL: 'until',       // Blocked until condition met
  DURING: 'during',     // Blocked while condition is active
  ALLOW_DURING: 'allowDuring' // Allowed only while condition is active
};

// ============ USER CONFIG ============
// Set your usernames for personal ping detection
const USER_CONFIG = {
  discord: '',     // e.g., 'rhodes' (without #1234)
  twitter: '',     // e.g., 'rhodesai'
  slack: '',       // e.g., 'rhodes'
};

// Ping window duration (3 minutes after personal ping)
const PING_WINDOW_DURATION_MS = 3 * 60 * 1000;

// Generic mentions that DON'T count as personal ping
const GENERIC_MENTIONS = [
  '@everyone', '@here', '@channel', '@all', '@room', '@team'
];

// ============ PING WINDOW TRACKING ============
// Stored in chrome.storage.local as { pingWindows: { channelId: expiryTimestamp } }

async function getPingWindows() {
  const data = await chrome.storage.local.get('pingWindows');
  return data.pingWindows || {};
}

async function setPingWindow(channelId) {
  const windows = await getPingWindows();
  windows[channelId] = Date.now() + PING_WINDOW_DURATION_MS;
  await chrome.storage.local.set({ pingWindows: windows });
  console.log('[TotalControl] Ping window opened for:', channelId);
}

async function isPingWindowActive(channelId) {
  const windows = await getPingWindows();
  if (!windows[channelId]) return false;
  if (Date.now() > windows[channelId]) {
    // Expired - clean up
    delete windows[channelId];
    await chrome.storage.local.set({ pingWindows: windows });
    return false;
  }
  return true;
}

// ============ MUTUAL PROTECTION SYSTEM ============
// Two extensions watch each other - can't disable both at once

// This is the PROTECTOR extension
const IS_PROTECTOR = true;
const PARTNER_EXTENSION_ID = '';  // Set after installing main TotalControl extension

// Set uninstall URL
chrome.runtime.setUninstallURL('https://totalcontrol.local/protector-uninstalled');

// Watch for partner extension being disabled/uninstalled
async function checkPartnerExtension() {
  if (!PARTNER_EXTENSION_ID) return; // Not configured yet

  try {
    const info = await chrome.management.get(PARTNER_EXTENSION_ID);

    if (!info.enabled) {
      // Partner is disabled! Alert and take over
      console.log('[Protector] Partner extension DISABLED - taking over');
      onPartnerDisabled();
    }
  } catch (e) {
    // Extension not found - uninstalled!
    console.log('[Protector] Partner extension UNINSTALLED - taking over');
    onPartnerUninstalled();
  }
}

async function onPartnerDisabled() {
  console.log('[Protector] Re-enabling partner extension...');

  // RE-ENABLE the partner extension!
  try {
    await chrome.management.setEnabled(PARTNER_EXTENSION_ID, true);
    console.log('[Protector] Partner re-enabled successfully');
    logProtectionEvent('partner_reenabled', { partnerId: PARTNER_EXTENSION_ID });
  } catch (e) {
    console.log('[Protector] Could not re-enable partner:', e);
    // Only show intervention if re-enable fails
    chrome.tabs.create({
      url: chrome.runtime.getURL('intervention.html'),
      active: true
    });
    logProtectionEvent('partner_disabled_reenable_failed', { partnerId: PARTNER_EXTENSION_ID, error: e.message });
  }
}

function onPartnerUninstalled() {
  // Open intervention tab
  chrome.tabs.create({
    url: chrome.runtime.getURL('intervention.html'),
    active: true
  });

  // Log event
  logProtectionEvent('partner_uninstalled', { partnerId: PARTNER_EXTENSION_ID });
}

// Check partner every 5 seconds
chrome.alarms.create('checkPartner', { periodInMinutes: 0.1 }); // ~6 seconds

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'checkPartner') {
    checkPartnerExtension();
  }
});

// Also check on management events
if (chrome.management) {
  chrome.management.onDisabled.addListener((info) => {
    if (info.id === PARTNER_EXTENSION_ID) {
      onPartnerDisabled();
    }
  });

  chrome.management.onUninstalled.addListener((id) => {
    if (id === PARTNER_EXTENSION_ID) {
      onPartnerUninstalled();
    }
  });
}

// Heartbeat system - desktop app monitors this
let heartbeatInterval = null;
const HEARTBEAT_INTERVAL = 10000; // 10 seconds

function startHeartbeat() {
  if (heartbeatInterval) return;

  // Immediate heartbeat
  sendHeartbeat();

  heartbeatInterval = setInterval(sendHeartbeat, HEARTBEAT_INTERVAL);
}

async function sendHeartbeat() {
  const timestamp = Date.now();
  await chrome.storage.local.set({
    extensionHeartbeat: timestamp,
    extensionActive: true,
    extensionVersion: chrome.runtime.getManifest().version
  });

  // Also try native messaging to desktop app if available
  try {
    chrome.runtime.sendNativeMessage('com.rhodesai.totalcontrol', {
      type: 'heartbeat',
      timestamp
    });
  } catch (e) {
    // Native host not available - that's ok
  }
}

// Detect suspension (extension being disabled/uninstalled)
chrome.runtime.onSuspend.addListener(() => {
  console.log('[TotalControl] Extension suspending - logging event');
  // Try to notify desktop app
  try {
    chrome.runtime.sendNativeMessage('com.rhodesai.totalcontrol', {
      type: 'extension_suspending',
      timestamp: Date.now()
    });
  } catch (e) {}
});

// Watch for OTHER extensions being uninstalled (if we have management permission)
if (chrome.management) {
  chrome.management.onUninstalled.addListener((id) => {
    // Could watch for a companion extension here
    console.log('[TotalControl] Extension uninstalled:', id);
  });

  chrome.management.onDisabled.addListener((info) => {
    console.log('[TotalControl] Extension disabled:', info.id);
  });
}

// Start heartbeat on load
startHeartbeat();

// Log protection events
async function logProtectionEvent(type, data) {
  const events = (await chrome.storage.local.get('protectionEvents')).protectionEvents || [];
  events.push({
    type,
    data,
    timestamp: new Date().toISOString()
  });
  if (events.length > 100) events.shift();
  await chrome.storage.local.set({ protectionEvents: events });
}

// Check if text contains a PERSONAL mention (not @everyone/@here)
function hasPersonalPing(text, platform) {
  if (!text) return false;
  const textLower = text.toLowerCase();

  // Check for generic mentions - these don't count
  const hasGeneric = GENERIC_MENTIONS.some(g => textLower.includes(g.toLowerCase()));

  // Check for personal mention based on configured username
  const username = USER_CONFIG[platform];
  if (username) {
    const userLower = username.toLowerCase();
    // @username mention
    if (textLower.includes('@' + userLower)) {
      return true;
    }
  }

  // Check for "replied to you" / "mentioned you" patterns
  const personalPatterns = [
    'replied to you',
    'mentioned you',
    'tagged you',
  ];

  return personalPatterns.some(p => textLower.includes(p));
}

// Music indicators - URLs/titles/descriptions containing these are allowed on YouTube
// From BlockerService.kt (lines 84-96) + record labels + artists markers
const MUSIC_INDICATORS = [
  // Title/URL indicators
  'music video',
  'official video',
  'official audio',
  'lyrics',
  'vevo',
  'topic',
  'official music',
  'audio only',
  'visualizer',
  'music.youtube.com',
  'ft.',
  'feat.',
  'official mv',
  '(audio)',
  'live performance',
  'concert',
  'acoustic',
  'music premiere',
  'audio',
  'mv',
  '(official)',

  // Record labels (check description)
  'universal music',
  'sony music',
  'warner music',
  'atlantic records',
  'interscope',
  'columbia records',
  'rca records',
  'capitol records',
  'def jam',
  'republic records',
  'island records',
  'virgin records',
  'parlophone',
  'epic records',
  'elektra',
  'geffen',
  'motown',
  'arista',

  // Music markers in description
  '℗',  // Phonogram copyright symbol
  '©',  // Copyright symbol often with label
  'auto-generated by youtube',
  'provided to youtube',
  'released on:',
  'artist:',
  'album:',
  'licensed to youtube',
  'music courtesy of',
  'stream/download',
  'spotify',
  'apple music',
  'itunes',
  'available now'
];

// Check if YouTube content indicates music based on full metadata
function isMusicVideo(url, title = '', description = '', channel = '', category = '') {
  const combined = [url, title, description, channel, category]
    .join(' ')
    .toLowerCase();

  // Check category first - if it's "Music", definitely allow
  if (category.toLowerCase() === 'music') {
    return true;
  }

  // Check for music indicators in combined text
  return MUSIC_INDICATORS.some(indicator =>
    combined.includes(indicator.toLowerCase())
  );
}

// Default blocked domains by category
const CATEGORIES = {
  'Social Media': ['facebook.com', 'instagram.com', 'twitter.com', 'x.com', 'tiktok.com', 'snapchat.com', 'linkedin.com', 'pinterest.com', 'reddit.com'],
  'Streaming': ['netflix.com', 'youtube.com', 'hulu.com', 'disneyplus.com', 'hbomax.com', 'max.com', 'twitch.tv', 'primevideo.com', 'spotify.com'],
  'Messaging': ['whatsapp.com', 'web.whatsapp.com', 'telegram.org', 'discord.com', 'slack.com', 'messenger.com'],
  'Gaming': ['store.steampowered.com', 'epicgames.com', 'roblox.com', 'minecraft.net'],
  'News': ['cnn.com', 'bbc.com', 'foxnews.com', 'nytimes.com'],
  'Dating': ['tinder.com', 'bumble.com', 'hinge.co', 'okcupid.com', 'match.com']
};

// Initialize storage with defaults
chrome.runtime.onInstalled.addListener(async () => {
  const existing = await chrome.storage.local.get(['rules', 'progress']);
  if (!existing.rules) {
    await chrome.storage.local.set({
      rules: [],
      progress: { steps: 0, workout: 0 },
      categories: CATEGORIES
    });
  }
  console.log('[TotalControl] Extension installed');
});

// Ensure default rules exist on startup
chrome.runtime.onStartup.addListener(ensureDefaultRules);

// Force add default rules on extension load
(async () => {
  await ensureDefaultRules();
  console.log('[TotalControl] Extension ready, default rules ensured');
})();

async function ensureDefaultRules() {
  const { rules } = await chrome.storage.local.get(['rules']);
  let existing = rules || [];

  // Remove old auto-generated rules to refresh them
  existing = existing.filter(r => {
    const id = r.id || '';
    // Keep user-created rules, remove auto-generated ones
    return !id.startsWith('youtube-block-') &&
           !id.startsWith('twitter-block-') &&
           !id.startsWith('discord-block-');
  });

  const now = Date.now();

  // YouTube rule: Block videos, allow music
  // Path-based exceptions (music detection) handled in shouldBlock()
  existing.push({
    id: 'youtube-block-' + now,
    items: ['youtube.com', 'youtu.be'],
    mode: 'until',
    condition: { type: 'tomorrow' },
    exceptions: ['music.youtube.com'],  // Subdomain exception
    enabled: true,
    createdAt: new Date().toISOString()
  });

  // Twitter/X rule: Block feed, allow DMs/chat
  // Path-based exceptions (/i/chat, /messages, /notifications) handled in shouldBlock()
  existing.push({
    id: 'twitter-block-' + now,
    items: ['twitter.com', 'x.com'],
    mode: 'until',
    condition: { type: 'tomorrow' },
    exceptions: [],  // Path exceptions handled in shouldBlock
    enabled: true,
    createdAt: new Date().toISOString()
  });

  // Discord rule: Block servers, allow DMs
  // Path-based exceptions (/channels/@me) handled in shouldBlock()
  existing.push({
    id: 'discord-block-' + now,
    items: ['discord.com', 'discordapp.com'],
    mode: 'until',
    condition: { type: 'tomorrow' },
    exceptions: [],  // Path exceptions handled in shouldBlock
    enabled: true,
    createdAt: new Date().toISOString()
  });

  // Other video platforms - blocked with music detection where applicable
  existing.push({
    id: 'video-platforms-' + now,
    items: [
      // Western
      'vimeo.com',
      'dailymotion.com',
      'twitch.tv',
      'tiktok.com',
      // Russian
      'rutube.ru',
      'vk.com/video',
      'ok.ru',
      'dzen.ru',
      'yandex.ru/video',
      // Chinese
      'bilibili.com',
      'iqiyi.com',
      // Japanese
      'nicovideo.jp',
      // Other
      'rumble.com',
      'bitchute.com',
      'odysee.com'
    ],
    mode: 'until',
    condition: { type: 'tomorrow' },
    exceptions: [],  // Music detection handled in shouldBlock for applicable sites
    enabled: true,
    createdAt: new Date().toISOString()
  });

  await chrome.storage.local.set({ rules: existing });
  console.log('[TotalControl] Default rules active:', existing.length, 'rules');
  console.log('[TotalControl] YouTube: blocked (music.youtube.com & music videos allowed)');
  console.log('[TotalControl] Twitter/X: blocked (DMs/chat/notifications allowed)');
  console.log('[TotalControl] Discord: blocked (DMs allowed)');
  console.log('[TotalControl] Video platforms: Vimeo, Dailymotion, Twitch, TikTok, Rutube, VK, Bilibili, etc.');
}

// Check if URL should be blocked
async function shouldBlock(url) {
  try {
    const hostname = new URL(url).hostname.replace('www.', '');
    const { rules, progress } = await chrome.storage.local.get(['rules', 'progress']);

    if (!rules || rules.length === 0) return { blocked: false };

    for (const rule of rules) {
      if (!rule.enabled) continue;

      // Support both old (blockedItems) and new (items) field names
      const ruleItems = rule.items || rule.blockedItems || [];
      const ruleMode = rule.mode || RuleMode.UNTIL;

      // Check if this hostname matches any item in the rule
      const matchesRule = ruleItems.some(item => {
        const itemLower = item.toLowerCase();
        return hostname.includes(itemLower) || itemLower.includes(hostname);
      });

      if (matchesRule) {
        // Check for subdomain exceptions (e.g., music.youtube.com excepts youtube.com block)
        const ruleExceptions = rule.exceptions || [];
        const isSubdomainException = ruleExceptions.some(ex => {
          const exLower = ex.toLowerCase();
          // Hostname must EXACTLY match or be a subdomain of the exception
          // e.g., exception 'music.youtube.com' allows 'music.youtube.com' but NOT 'youtube.com'
          return hostname === exLower || hostname.endsWith('.' + exLower);
        });

        if (isSubdomainException) {
          console.log('[TotalControl] Subdomain exception matched:', hostname);
          continue;
        }

        // URL-path based exceptions for chat/messaging (always allowed)
        const urlLower = url.toLowerCase();
        const pathname = new URL(url).pathname.toLowerCase();

        // Twitter/X: 1-on-1 DMs allowed, group chats need personal ping
        if (hostname.includes('twitter.com') || hostname.includes('x.com')) {
          // 1-on-1 DM: /i/chat/[numeric] (NOT /i/chat/g...)
          if (pathname.match(/^\/i\/chat\/\d+$/) || pathname === '/i/chat') {
            console.log('[TotalControl] Twitter 1-on-1 DM allowed:', pathname);
            continue;
          }
          // Messages list and notifications always allowed
          if (pathname.startsWith('/messages') || pathname === '/notifications') {
            console.log('[TotalControl] Twitter messages/notifications allowed:', pathname);
            continue;
          }
          // Group chats /i/chat/g... need ping window
          if (pathname.match(/^\/i\/chat\/g/)) {
            const groupId = pathname.split('/').pop();
            const windowActive = await isPingWindowActive('twitter:' + groupId);
            if (windowActive) {
              console.log('[TotalControl] Twitter group allowed (ping window):', pathname);
              continue;
            }
            console.log('[TotalControl] Twitter group BLOCKED (no ping):', pathname);
            // Fall through to block
          }
        }

        // Discord: 1-on-1 DMs allowed, server channels need personal ping
        if (hostname.includes('discord.com') || hostname.includes('discordapp.com')) {
          // DMs: /channels/@me or /channels/@me/[id] - always allowed
          if (pathname.match(/^\/channels\/@me(\/\d+)?$/)) {
            console.log('[TotalControl] Discord DM allowed:', pathname);
            continue;
          }
          // Server channels: /channels/[server]/[channel] - need ping
          const serverMatch = pathname.match(/^\/channels\/(\d+)\/(\d+)/);
          if (serverMatch) {
            const channelId = serverMatch[2];
            const windowActive = await isPingWindowActive('discord:' + channelId);
            if (windowActive) {
              console.log('[TotalControl] Discord server allowed (ping window):', pathname);
              continue;
            }
            console.log('[TotalControl] Discord server BLOCKED (no ping):', pathname);
            // Fall through to block
          }
        }

        // YouTube: Music-only mode - block feed/videos, allow search bar
        if (hostname.includes('youtube.com') || hostname.includes('youtu.be')) {
          // music.youtube.com is already handled by subdomain exception above
          const ytPath = pathname;

          // Always allow: search results (to find music)
          if (ytPath.startsWith('/results')) {
            console.log('[TotalControl] YouTube search allowed:', ytPath);
            continue;
          }

          // For /watch and /shorts - check if music video
          if (ytPath.startsWith('/watch') || ytPath.startsWith('/shorts')) {
            if (isMusicVideo(url)) {
              console.log('[TotalControl] Music video detected (URL), allowing:', url);
              continue;
            }
            // Not detected as music via URL - will be blocked
            // Content script will do full title/description check
          }

          // Homepage, feed, etc - BLOCK but with partial overlay (search bar visible)
          // Content script will handle showing partial overlay
        }

        // Other video platforms: Music-only mode
        // VK: Allow music section
        if (hostname.includes('vk.com')) {
          if (pathname.startsWith('/music') || pathname.startsWith('/audio')) {
            console.log('[TotalControl] VK music allowed:', pathname);
            continue;
          }
        }

        // Twitch: Allow music/DJ category
        if (hostname.includes('twitch.tv')) {
          if (urlLower.includes('/directory/game/music') ||
              urlLower.includes('category=music') ||
              pathname.startsWith('/directory/all/tags/music')) {
            console.log('[TotalControl] Twitch music category allowed');
            continue;
          }
        }

        // Dailymotion: Allow music category
        if (hostname.includes('dailymotion.com')) {
          if (pathname.startsWith('/music') || urlLower.includes('channel=music')) {
            console.log('[TotalControl] Dailymotion music allowed');
            continue;
          }
        }

        // Yandex/Dzen: Allow music
        if (hostname.includes('dzen.ru') || hostname.includes('yandex.ru')) {
          if (pathname.includes('/music')) {
            console.log('[TotalControl] Yandex/Dzen music allowed');
            continue;
          }
        }

        // Bilibili: Allow music section
        if (hostname.includes('bilibili.com')) {
          if (pathname.startsWith('/v/music') || pathname.includes('music')) {
            console.log('[TotalControl] Bilibili music allowed');
            continue;
          }
        }

        // Check if condition is met/active
        const conditionResult = checkCondition(rule.condition, progress);

        // Determine if blocked based on mode
        let isBlocked = false;
        switch (ruleMode) {
          case RuleMode.UNTIL:
            // Blocked until condition is met
            isBlocked = !conditionResult.met;
            break;
          case RuleMode.DURING:
            // Blocked while condition is active
            isBlocked = conditionResult.met;
            break;
          case RuleMode.ALLOW_DURING:
            // Blocked unless condition is active
            isBlocked = !conditionResult.met;
            break;
        }

        if (isBlocked) {
          return {
            blocked: true,
            rule: rule,
            mode: ruleMode,
            status: conditionResult.status,
            progress: conditionResult.progress
          };
        }
      }
    }
    return { blocked: false };
  } catch (e) {
    console.error('[TotalControl] Error checking URL:', e);
    return { blocked: false };
  }
}

// Check if condition is met/active
function checkCondition(condition, progress) {
  const now = new Date();

  switch (condition.type) {
    case 'steps':
      const stepsTarget = condition.stepsTarget || condition.steps_target || 10000;
      const stepsMet = (progress.steps || 0) >= stepsTarget;
      const stepsPct = Math.min(100, Math.round((progress.steps || 0) / stepsTarget * 100));
      return {
        met: stepsMet,
        status: `${progress.steps || 0}/${stepsTarget} steps`,
        progress: stepsPct
      };

    case 'time':
      const [targetHour, targetMin] = (condition.timeTarget || condition.time_target || '17:00').split(':').map(Number);
      const target = new Date(now.getFullYear(), now.getMonth(), now.getDate(), targetHour, targetMin || 0);
      const timeMet = now >= target;
      if (timeMet) {
        return { met: true, status: 'Time reached', progress: 100 };
      }
      const minsLeft = Math.round((target - now) / 60000);
      const totalMins = targetHour * 60 + (targetMin || 0);
      const currentMins = now.getHours() * 60 + now.getMinutes();
      const timePct = Math.min(100, Math.round(currentMins / totalMins * 100));
      return {
        met: false,
        status: minsLeft > 60 ? `${Math.floor(minsLeft/60)}h ${minsLeft%60}m left` : `${minsLeft}m left`,
        progress: timePct
      };

    case 'timeRange':
      // Time range for DURING rules (e.g., 09:00 - 17:00)
      const timeRange = condition.timeRange || condition.time_range;
      if (timeRange) {
        const [startHour, startMin] = (timeRange.startTime || timeRange.start || '09:00').split(':').map(Number);
        const [endHour, endMin] = (timeRange.endTime || timeRange.end || '17:00').split(':').map(Number);
        const startMins = startHour * 60 + (startMin || 0);
        const endMins = endHour * 60 + (endMin || 0);
        const nowMins = now.getHours() * 60 + now.getMinutes();

        let isActive;
        if (endMins > startMins) {
          // Normal range: 09:00-17:00
          isActive = nowMins >= startMins && nowMins < endMins;
        } else {
          // Overnight range: 22:00-06:00
          isActive = nowMins >= startMins || nowMins < endMins;
        }
        const rangeDesc = `${timeRange.startTime || timeRange.start} - ${timeRange.endTime || timeRange.end}`;
        return {
          met: isActive,
          status: isActive ? `In range (${rangeDesc})` : `Outside range (${rangeDesc})`,
          progress: isActive ? 100 : 0
        };
      }
      return { met: false, status: 'No time range set', progress: 0 };

    case 'workout':
      const workoutTarget = condition.workoutMinutes || condition.workout_minutes || 30;
      const workoutMet = (progress.workout || 0) >= workoutTarget;
      const workoutPct = Math.min(100, Math.round((progress.workout || 0) / workoutTarget * 100));
      return {
        met: workoutMet,
        status: `${progress.workout || 0}/${workoutTarget} min`,
        progress: workoutPct
      };

    case 'schedule':
      // Day-based schedule (weekdays/weekends)
      const schedule = condition.schedule;
      if (schedule && schedule.days) {
        const today = now.getDay() === 0 ? 7 : now.getDay(); // 1=Mon, 7=Sun
        const isActive = schedule.days.includes(today);
        let desc = 'custom';
        if (schedule.days.length === 5 && !schedule.days.includes(6) && !schedule.days.includes(7)) {
          desc = 'weekdays';
        } else if (schedule.days.length === 2 && schedule.days.includes(6) && schedule.days.includes(7)) {
          desc = 'weekends';
        }
        return {
          met: isActive,
          status: isActive ? `Active (${desc})` : `Inactive (${desc})`,
          progress: isActive ? 100 : 0
        };
      }
      return { met: false, status: 'No schedule set', progress: 0 };

    case 'location':
      // Location-based (not fully implemented in extension)
      return { met: false, status: 'Location check (app only)', progress: 0 };

    case 'tomorrow':
      return { met: false, status: 'Blocked until tomorrow', progress: 0 };

    case 'password':
      return { met: false, status: 'Enter password to unlock', progress: 0 };

    default:
      return { met: false, status: 'Unknown condition', progress: 0 };
  }
}

// Listen for messages from content script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'CHECK_BLOCK') {
    shouldBlock(message.url).then(result => {
      sendResponse(result);
    });
    return true; // Keep channel open for async response
  }

  // Check block with title (for YouTube music detection)
  if (message.type === 'CHECK_BLOCK_WITH_TITLE') {
    const { url, title } = message;
    // If it's YouTube and a music video, allow it
    if (isMusicVideo(url, title)) {
      console.log('[TotalControl] Music video detected via title, allowing:', title);
      sendResponse({ blocked: false, reason: 'music_video' });
      return true;
    }
    // Otherwise do normal check
    shouldBlock(url).then(result => {
      sendResponse(result);
    });
    return true;
  }

  // Full YouTube video check with description, channel, category
  if (message.type === 'CHECK_YOUTUBE_VIDEO') {
    const { url, title, description, channel, category } = message;

    // Check if it's a music video based on all metadata
    if (isMusicVideo(url, title, description, channel, category)) {
      console.log('[TotalControl] Music video detected, allowing:', title);
      console.log('[TotalControl] Indicators found in:', { title, channel, category, descSnippet: description.slice(0, 200) });
      sendResponse({ blocked: false, reason: 'music_video' });
      return true;
    }

    // Not a music video - check if YouTube should be blocked
    console.log('[TotalControl] NOT a music video, checking block:', title);
    shouldBlock(url).then(result => {
      sendResponse(result);
    });
    return true;
  }

  if (message.type === 'GET_RULES') {
    chrome.storage.local.get(['rules', 'progress', 'categories']).then(data => {
      sendResponse(data);
    });
    return true;
  }

  if (message.type === 'SAVE_RULES') {
    chrome.storage.local.set({ rules: message.rules }).then(() => {
      sendResponse({ success: true });
    });
    return true;
  }

  if (message.type === 'ADD_RULE') {
    addRule(message.rule).then(rule => {
      sendResponse({ success: true, rule });
    });
    return true;
  }

  if (message.type === 'UPDATE_PROGRESS') {
    chrome.storage.local.set({ progress: message.progress }).then(() => {
      sendResponse({ success: true });
    });
    return true;
  }
});

// Web navigation listener - check before page loads
chrome.webNavigation.onBeforeNavigate.addListener(async (details) => {
  if (details.frameId !== 0) return; // Only main frame

  const result = await shouldBlock(details.url);
  if (result.blocked) {
    // Send message to content script to show block overlay
    try {
      await chrome.tabs.sendMessage(details.tabId, {
        type: 'SHOW_BLOCK',
        rule: result.rule,
        status: result.status,
        progress: result.progress
      });
    } catch (e) {
      // Content script not ready yet, it will check on load
    }
  }
});

console.log('[TotalControl] Background service worker started');
