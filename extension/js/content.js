// TotalControl Content Script
// Shows block overlay on blocked sites

let isBlocked = false;
let blockOverlay = null;
let checkInProgress = false;

// Debug indicator
console.log('[TotalControl] Content script loaded on:', window.location.hostname);

// Get YouTube video metadata (description, channel, etc.)
function getYouTubeMetadata() {
  const metadata = {
    title: document.title || '',
    description: '',
    channel: '',
    category: ''
  };

  try {
    // Get description from the page
    // YouTube stores it in a few places
    const descriptionEl = document.querySelector('#description-inline-expander, #description yt-formatted-string, meta[name="description"]');
    if (descriptionEl) {
      metadata.description = descriptionEl.textContent || descriptionEl.getAttribute('content') || '';
    }

    // Get channel name
    const channelEl = document.querySelector('#channel-name a, #owner-name a, ytd-channel-name a');
    if (channelEl) {
      metadata.channel = channelEl.textContent || '';
    }

    // Check for VEVO badge or Topic channel
    const badges = document.querySelectorAll('ytd-badge-supported-renderer, .badge');
    badges.forEach(badge => {
      const text = badge.textContent || '';
      if (text.includes('VEVO') || text.includes('Official Artist')) {
        metadata.channel += ' VEVO';
      }
    });

    // Check for "Music" category in video info
    const categoryLinks = document.querySelectorAll('ytd-metadata-row-renderer a');
    categoryLinks.forEach(link => {
      if (link.href && link.href.includes('/channel/') && link.textContent) {
        const text = link.textContent.toLowerCase();
        if (text.includes('music')) {
          metadata.category = 'Music';
        }
      }
    });

    // Also check structured data
    const scripts = document.querySelectorAll('script[type="application/ld+json"]');
    scripts.forEach(script => {
      try {
        const data = JSON.parse(script.textContent);
        if (data.genre) metadata.category = data.genre;
        if (data.description) metadata.description = data.description;
      } catch (e) {}
    });

  } catch (e) {
    console.error('[TotalControl] Error getting YouTube metadata:', e);
  }

  return metadata;
}

// Check if extension context is still valid
function isExtensionValid() {
  try {
    return !!(chrome.runtime && chrome.runtime.id);
  } catch (e) {
    return false;
  }
}

// Check if current page should be blocked
async function checkCurrentPage() {
  // Skip if extension was reloaded (context invalidated)
  if (!isExtensionValid()) {
    console.log('[TotalControl] Extension context invalidated, skipping check');
    return;
  }

  // Prevent overlapping checks (causes flicker)
  if (checkInProgress) {
    console.log('[TotalControl] Check already in progress, skipping');
    return;
  }
  checkInProgress = true;

  try {
    const url = window.location.href;
    const hostname = window.location.hostname;

    // For YouTube, get full metadata for music video detection
    const isYouTube = hostname.includes('youtube.com') || hostname.includes('youtu.be');
    const isVideoPage = url.includes('/watch') || url.includes('youtu.be/');

    let response;
    if (isYouTube && isVideoPage) {
      // Get YouTube metadata (title, description, channel)
      let metadata = getYouTubeMetadata();

      // Wait for title to load if it's still generic (YouTube loads async)
      if (!metadata.title || metadata.title === 'YouTube' || metadata.title.startsWith('YouTube')) {
        console.log('[TotalControl] Waiting for YouTube title to load...');
        await new Promise(resolve => setTimeout(resolve, 1500));
        metadata = getYouTubeMetadata();
      }

      console.log('[TotalControl] YouTube metadata:', metadata);

      // Check with full metadata for music video detection
      response = await chrome.runtime.sendMessage({
        type: 'CHECK_YOUTUBE_VIDEO',
        url: url,
        title: metadata.title,
        description: metadata.description,
        channel: metadata.channel,
        category: metadata.category
      });

      // Clear any existing overlays first for clean transition
      removeBlockOverlay();
      removeMusicModeOverlay();

      // If it's a music video, show video overlay but allow audio to play
      if (response && response.reason === 'music_video') {
        console.log('[TotalControl] Music video - covering video, allowing audio:', metadata.title);
        showMusicModeOverlay();
        return;
      }
    } else if (isYouTube) {
      // YouTube but not video page (homepage, search, etc.)
      response = await chrome.runtime.sendMessage({
        type: 'CHECK_BLOCK',
        url: url
      });
    } else {
      response = await chrome.runtime.sendMessage({
        type: 'CHECK_BLOCK',
        url: url
      });
    }

    if (response && response.blocked) {
      showBlockOverlay(response.rule, response.status, response.progress);
    } else {
      removeBlockOverlay();
    }
  } catch (e) {
    // Handle extension context invalidated error gracefully
    if (e.message && e.message.includes('Extension context invalidated')) {
      console.log('[TotalControl] Extension reloaded, please refresh the page');
      return;
    }
    console.error('[TotalControl] Error checking page:', e);
  } finally {
    checkInProgress = false;
  }
}

// Mute all videos on the page
function muteAllVideos() {
  const videos = document.querySelectorAll('video');
  videos.forEach(video => {
    video.muted = true;
    video.pause();
  });
  // Also try to pause YouTube player specifically
  const ytPlayer = document.querySelector('#movie_player');
  if (ytPlayer && ytPlayer.pauseVideo) {
    try { ytPlayer.pauseVideo(); } catch (e) {}
  }
}

// Unmute videos (when unblocked)
function unmuteAllVideos() {
  const videos = document.querySelectorAll('video');
  videos.forEach(video => {
    video.muted = false;
  });
}

// Show music mode overlay - covers video but allows audio to play
function showMusicModeOverlay() {
  // Don't add if already exists
  if (document.getElementById('totalcontrol-music-overlay')) return;

  // Inject CSS for music mode
  const style = document.createElement('style');
  style.id = 'totalcontrol-music-style';
  style.textContent = `
    /* Music mode overlay - covers video fully */
    #totalcontrol-music-overlay {
      position: absolute !important;
      top: 0 !important;
      left: 0 !important;
      right: 0 !important;
      bottom: 0 !important;
      background: #1a1a0f !important;
      z-index: 59 !important;
      display: flex !important;
      flex-direction: column !important;
      align-items: center !important;
      justify-content: center !important;
      font-family: 'Courier New', monospace !important;
    }
    #totalcontrol-music-overlay .tc-logo {
      font-size: 28px;
      font-weight: bold;
      color: #ffb000;
      letter-spacing: 4px;
      margin-bottom: 5px;
      text-shadow: 0 0 10px rgba(255, 176, 0, 0.5);
    }
    #totalcontrol-music-overlay .tc-logo-sub {
      font-size: 12px;
      color: #6b6348;
      letter-spacing: 2px;
      margin-bottom: 25px;
      font-style: italic;
    }
    #totalcontrol-music-overlay .tc-music-icon {
      font-size: 60px;
      margin-bottom: 15px;
    }
    #totalcontrol-music-overlay .tc-music-title {
      color: #ffb000;
      font-size: 20px;
      font-weight: bold;
      margin-bottom: 15px;
      letter-spacing: 2px;
    }
    #totalcontrol-music-overlay .tc-video-title {
      color: #d4c4a0;
      font-size: 16px;
      margin-bottom: 10px;
      max-width: 80%;
      text-align: center;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    #totalcontrol-music-overlay .tc-music-subtitle {
      color: #6b6348;
      font-size: 14px;
    }
    /* Keep YouTube controls clickable but in normal position */
    .ytp-chrome-bottom, .ytp-chrome-controls {
      z-index: 70 !important;
    }
    .ytp-progress-bar-container {
      z-index: 70 !important;
    }
    .ytp-popup, .ytp-settings-menu {
      z-index: 80 !important;
    }
    #movie_player, .html5-video-player {
      position: relative !important;
    }
  `;
  document.head.appendChild(style);

  const addOverlay = () => {
    if (document.getElementById('totalcontrol-music-overlay')) return;

    const player = document.querySelector('#movie_player');
    if (player) {
      // Get video title
      const videoTitle = document.querySelector('h1.ytd-video-primary-info-renderer, h1.ytd-watch-metadata yt-formatted-string, #title h1')?.textContent?.trim() || document.title.replace(' - YouTube', '').trim();

      const overlay = document.createElement('div');
      overlay.id = 'totalcontrol-music-overlay';
      overlay.innerHTML = `
        <div class="tc-logo">TOTAL CONTROL</div>
        <div class="tc-logo-sub">A Rhodes Program</div>
        <div class="tc-music-icon">🎵</div>
        <div class="tc-music-title">AUDIO ONLY MODE</div>
        <div class="tc-video-title">${videoTitle}</div>
        <div class="tc-music-subtitle">Video hidden • Audio playing</div>
      `;
      player.appendChild(overlay);
      console.log('[TotalControl] Music mode overlay added');
    }
  };

  // Try multiple times for YouTube async loading
  addOverlay();
  setTimeout(addOverlay, 300);
  setTimeout(addOverlay, 800);
  setTimeout(addOverlay, 1500);
  setTimeout(addOverlay, 3000);

  // Watch for player appearing
  const observer = new MutationObserver(() => {
    if (!document.getElementById('totalcontrol-music-overlay')) {
      addOverlay();
    }
  });
  observer.observe(document.body, { childList: true, subtree: true });
  window.tcMusicObserver = observer;
}

// Remove music mode overlay
function removeMusicModeOverlay() {
  const overlay = document.getElementById('totalcontrol-music-overlay');
  if (overlay) overlay.remove();

  const style = document.getElementById('totalcontrol-music-style');
  if (style) style.remove();

  if (window.tcMusicObserver) {
    window.tcMusicObserver.disconnect();
    window.tcMusicObserver = null;
  }
}

// Create and show the block overlay
function showBlockOverlay(rule, status, progress) {
  if (blockOverlay) return; // Already showing

  isBlocked = true;

  // Mute and pause all videos - this is a non-music block
  // (Music videos go through showMusicModeOverlay instead, which doesn't mute)
  muteAllVideos();

  // Check if this is a YouTube block
  const isYouTube = window.location.hostname.includes('youtube.com') || window.location.hostname.includes('youtu.be');
  const isVideoPage = window.location.pathname.includes('/watch') || window.location.hostname.includes('youtu.be');
  const ruleItems = (rule.items || rule.blockedItems || []);

  // Customize message for YouTube - ALWAYS show search bar
  let blockedText = 'BLOCKED';
  let ruleText = `NO ${ruleItems.slice(0, 3).join(', ')}${ruleItems.length > 3 ? ` +${ruleItems.length - 3}` : ''}`;
  let untilText = `UNTIL ${formatCondition(rule.condition)}`;
  let footerText = 'Focus on your goals. You\'ve got this.';
  let overlayStyle = '';

  if (isYouTube) {
    blockedText = 'MUSIC ONLY MODE';
    if (isVideoPage) {
      ruleText = 'This video is not available';
      untilText = 'Music videos are still allowed';
    } else {
      ruleText = 'Video feed is hidden';
      untilText = 'Search for music above - music videos are still allowed';
    }
    footerText = 'Music works on both YouTube and YouTube Music';
  }

  // Add music button for YouTube
  let musicButtonHtml = '';
  if (isYouTube) {
    musicButtonHtml = `
      <a href="https://music.youtube.com" class="tc-music-button">
        <svg viewBox="0 0 24 24" width="24" height="24" style="margin-right: 10px;">
          <path fill="currentColor" d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/>
        </svg>
        GO TO MUSIC
      </a>
    `;
  }

  // Create overlay container
  blockOverlay = document.createElement('div');
  blockOverlay.id = 'totalcontrol-overlay';

  // YouTube special handling: overlay video but keep controls accessible
  if (isYouTube) {
    // Inject CSS for YouTube-specific styling
    const ytStyle = document.createElement('style');
    ytStyle.id = 'totalcontrol-yt-style';

    if (isVideoPage) {
      // Video page: cover video but keep player controls accessible
      ytStyle.textContent = `
        /* Hide comments content but show container for our message */
        #comments #contents, ytd-comments #contents,
        #comments #header, ytd-comments #header {
          display: none !important;
        }
        /* Add our message in place of comments */
        #comments::before, ytd-comments::before {
          content: "Total Control has restricted comments for this video." !important;
          display: block !important;
          padding: 20px !important;
          color: #6b6348 !important;
          font-family: 'Courier New', monospace !important;
          font-size: 14px !important;
          text-align: center !important;
          background: #1a1a0f !important;
          border: 1px solid #3d3d2d !important;
          margin: 20px 0 !important;
        }
        /* Keep masthead visible */
        ytd-masthead, #masthead, #masthead-container {
          visibility: visible !important;
          z-index: 10000 !important;
        }
        /* Ensure player has positioning context */
        #movie_player, .html5-video-player {
          position: relative !important;
        }
        /* Video overlay - covers video area, leaves controls visible */
        #totalcontrol-video-overlay {
          position: absolute !important;
          top: 0 !important;
          left: 0 !important;
          right: 0 !important;
          bottom: 40px !important; /* Leave space for control bar */
          background: #1a1a0f !important;
          z-index: 59 !important; /* Below YouTube controls (z-index 60+) */
          display: flex !important;
          align-items: center !important;
          justify-content: center !important;
          font-family: 'Courier New', monospace !important;
          pointer-events: none !important; /* Let clicks through to video for play/pause */
        }
        #totalcontrol-video-overlay .tc-video-msg {
          display: flex;
          flex-direction: column;
          align-items: center;
          color: #ffb000;
          font-size: 18px;
          text-align: center;
          padding: 20px;
          pointer-events: auto !important;
          max-width: 90%;
        }
        #totalcontrol-video-overlay .tc-logo {
          font-size: 28px;
          font-weight: bold;
          color: #ffb000;
          letter-spacing: 4px;
          margin-bottom: 5px;
          text-shadow: 0 0 10px rgba(255, 176, 0, 0.5);
        }
        #totalcontrol-video-overlay .tc-logo-sub {
          font-size: 12px;
          color: #6b6348;
          letter-spacing: 2px;
          margin-bottom: 20px;
          font-style: italic;
        }
        #totalcontrol-video-overlay .tc-blocked-title {
          font-size: 24px;
          font-weight: bold;
          margin-bottom: 10px;
          color: #ff3333;
        }
        #totalcontrol-video-overlay .tc-video-name {
          color: #d4c4a0;
          font-size: 14px;
          margin-bottom: 15px;
          max-width: 90%;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        /* Keep YouTube controls ABOVE our overlay */
        .ytp-chrome-bottom, .ytp-chrome-controls {
          z-index: 70 !important;
        }
        /* Keep progress bar clickable */
        .ytp-progress-bar-container {
          z-index: 70 !important;
        }
        /* Settings menu needs to be on top */
        .ytp-popup, .ytp-settings-menu {
          z-index: 80 !important;
        }
      `;
    } else {
      // Non-video pages: hide feed content
      ytStyle.textContent = `
        /* Hide ALL YouTube content */
        ytd-browse, ytd-page-manager, #content, #page-manager,
        ytd-rich-grid-renderer, ytd-two-column-browse-results-renderer,
        #contents, ytd-browse[page-subtype="home"] #contents,
        ytd-watch-flexy, #primary, #secondary,
        ytd-watch, ytd-watch-grid, ytd-search {
          visibility: hidden !important;
        }
        /* Keep masthead (header with search bar) visible and on top */
        ytd-masthead, #masthead, #masthead-container, #container.ytd-masthead {
          visibility: visible !important;
          z-index: 10000 !important;
        }
        /* Keep search box functional */
        #search, #search-form, ytd-searchbox {
          visibility: visible !important;
        }
      `;
    }
    document.head.appendChild(ytStyle);

    // For video pages, add overlay directly on video player
    if (isVideoPage) {
      const addVideoOverlay = () => {
        // Don't add if already exists
        if (document.getElementById('totalcontrol-video-overlay')) return;

        const player = document.querySelector('#movie_player');
        if (player) {
          // Get video title - try multiple selectors for different YouTube layouts
          const titleEl = document.querySelector('ytd-watch-metadata h1 yt-formatted-string, h1.ytd-video-primary-info-renderer yt-formatted-string, #above-the-fold #title yt-formatted-string, h1.title');
          const videoTitle = titleEl?.textContent?.trim() || document.title.replace(' - YouTube', '').replace(/^\(\d+\)\s*/, '').trim();
          console.log('[TotalControl] Blocked video title:', videoTitle);

          const overlay = document.createElement('div');
          overlay.id = 'totalcontrol-video-overlay';
          overlay.innerHTML = `
            <div class="tc-video-msg">
              <div class="tc-logo">TOTAL CONTROL</div>
              <div class="tc-logo-sub">A Rhodes Program</div>
              <div class="tc-blocked-title">🚫 BLOCKED</div>
              <div class="tc-video-name">${videoTitle}</div>
              <div style="font-size: 14px; color: #6b6348;">
                This video is not available during focus mode
              </div>
            </div>
          `;
          player.appendChild(overlay);
          console.log('[TotalControl] Video overlay added to player');
        } else {
          console.log('[TotalControl] Player not found yet, will retry...');
        }
      };

      // Try immediately and with multiple delays
      addVideoOverlay();
      setTimeout(addVideoOverlay, 300);
      setTimeout(addVideoOverlay, 800);
      setTimeout(addVideoOverlay, 1500);
      setTimeout(addVideoOverlay, 3000);

      // Also watch for player appearing (YouTube loads async)
      const playerObserver = new MutationObserver(() => {
        if (!document.getElementById('totalcontrol-video-overlay')) {
          addVideoOverlay();
        }
      });
      playerObserver.observe(document.body, { childList: true, subtree: true });

      // Store observer to disconnect later
      window.tcPlayerObserver = playerObserver;
    }

    // Position overlay BELOW the masthead
    blockOverlay.classList.add('tc-youtube-partial');
  }
  blockOverlay.innerHTML = `
    <div class="tc-block-container">
      <div class="tc-header">TOTAL CONTROL</div>
      <div class="tc-subheader">A Rhodes Program</div>
      <div class="tc-lock-icon">
        <svg viewBox="0 0 24 24" width="80" height="80">
          <path fill="currentColor" d="M12 17a2 2 0 0 0 2-2 2 2 0 0 0-2-2 2 2 0 0 0-2 2 2 2 0 0 0 2 2m6-9a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2h1V6a5 5 0 0 1 5-5 5 5 0 0 1 5 5v2h1m-6-5a3 3 0 0 0-3 3v2h6V6a3 3 0 0 0-3-3z"/>
        </svg>
      </div>
      <div class="tc-message">
        <div class="tc-blocked-text">${blockedText}</div>
        <div class="tc-rule-text">${ruleText}</div>
        <div class="tc-until-text">${untilText}</div>
      </div>
      <div class="tc-progress-container">
        <div class="tc-progress-bar">
          <div class="tc-progress-fill" style="width: ${progress}%"></div>
        </div>
        <div class="tc-progress-text">${status}</div>
      </div>
      ${musicButtonHtml}
      <div class="tc-footer">
        ${footerText}
      </div>
    </div>
  `;

  // Add to page
  document.documentElement.appendChild(blockOverlay);

  // Prevent scrolling (but not on YouTube partial overlay - keep search usable)
  if (!isYouTube) {
    document.body.style.overflow = 'hidden';
    // Block all interactions only for full overlay
    document.addEventListener('keydown', blockEvent, true);
    document.addEventListener('click', blockEvent, true);
  } else {
    // For YouTube partial overlay, handle window resize to adjust overlay position
    const updateOverlayPosition = () => {
      const ytHeader = document.querySelector('ytd-masthead, #masthead, #masthead-container');
      if (ytHeader && blockOverlay) {
        const headerHeight = ytHeader.getBoundingClientRect().height;
        blockOverlay.style.top = headerHeight + 'px';
        blockOverlay.style.height = `calc(100vh - ${headerHeight}px)`;
      }
    };
    window.addEventListener('resize', updateOverlayPosition);
    // Update after a short delay in case YouTube header loads late
    setTimeout(updateOverlayPosition, 500);
    setTimeout(updateOverlayPosition, 1500);
    setTimeout(updateOverlayPosition, 3000);

    // Keep non-music videos muted while blocked
    window.tcMuteInterval = setInterval(() => {
      if (isBlocked) {
        muteAllVideos();
      }
    }, 1000);
  }
}

function formatCondition(condition) {
  switch (condition.type) {
    case 'steps':
      return `${(condition.stepsTarget || 10000).toLocaleString()} steps`;
    case 'time':
      return condition.timeTarget || '5:00 PM';
    case 'workout':
      return `${condition.workoutMinutes || 30}min workout`;
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

function blockEvent(e) {
  if (isBlocked) {
    // Allow clicks on links within the overlay (e.g., music.youtube.com link)
    if (e.type === 'click' && e.target.closest('a[href]')) {
      return; // Let the link work
    }
    e.preventDefault();
    e.stopPropagation();
  }
}

// Remove overlay (called when condition is met)
function removeBlockOverlay() {
  if (blockOverlay) {
    blockOverlay.remove();
    blockOverlay = null;
    isBlocked = false;
    document.body.style.overflow = '';
    document.removeEventListener('keydown', blockEvent, true);
    document.removeEventListener('click', blockEvent, true);
    // Remove YouTube content-hiding style if it exists
    const ytStyle = document.getElementById('totalcontrol-yt-style');
    if (ytStyle) {
      ytStyle.remove();
    }
    // Remove video overlay if it exists
    const videoOverlay = document.getElementById('totalcontrol-video-overlay');
    if (videoOverlay) {
      videoOverlay.remove();
    }
    // Clear mute interval
    if (window.tcMuteInterval) {
      clearInterval(window.tcMuteInterval);
      window.tcMuteInterval = null;
    }
    // Disconnect player observer
    if (window.tcPlayerObserver) {
      window.tcPlayerObserver.disconnect();
      window.tcPlayerObserver = null;
    }
  }
  // Also remove music mode overlay if present
  removeMusicModeOverlay();
}

// Listen for messages from background
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'SHOW_BLOCK') {
    showBlockOverlay(message.rule, message.status, message.progress);
    sendResponse({ success: true });
  }
  if (message.type === 'REMOVE_BLOCK') {
    removeBlockOverlay();
    sendResponse({ success: true });
  }
});

// Check on page load
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', checkCurrentPage);
} else {
  checkCurrentPage();
}

// Also check immediately for fast blocking
checkCurrentPage();

// Watch for YouTube navigation (SPA) and title changes
function setupYouTubeObserver() {
  if (!window.location.hostname.includes('youtube.com')) return;

  let lastUrl = window.location.href;
  let lastTitle = document.title;

  // Watch for URL changes (YouTube SPA navigation)
  setInterval(() => {
    if (window.location.href !== lastUrl) {
      lastUrl = window.location.href;
      setTimeout(checkCurrentPage, 1000); // Wait for page to load
    }
  }, 500);

  // Watch for title changes (video title loads async)
  const titleObserver = new MutationObserver(() => {
    if (document.title !== lastTitle) {
      lastTitle = document.title;
      setTimeout(checkCurrentPage, 500);
    }
  });

  // Only observe if head exists
  if (document.head) {
    titleObserver.observe(document.head, { childList: true, subtree: true });
  }
}

// Run observer setup when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', setupYouTubeObserver);
} else {
  setupYouTubeObserver();
}
