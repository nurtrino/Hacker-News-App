// AdFreeTube in-page ad remover.
//
// Network-level blocking (WKContentRuleList) handles banner/overlay/tracking
// requests, but in-stream video ads are served from the same googlevideo
// hosts as the real video, so they cannot be blocked by URL alone. This
// script watches the player and dispatches them as they appear:
//   * clicks the "Skip" button the instant it is enabled,
//   * fast-forwards unskippable ads to their end,
//   * removes ad/promoted DOM nodes that slip past the cosmetic CSS.
//
// Everything is defensive (lots of optional chaining / try-catch) because the
// YouTube DOM changes frequently and we must never break normal playback.
(function () {
  "use strict";

  if (window.__adFreeTubeInstalled) return;
  window.__adFreeTubeInstalled = true;

  function handleVideoAds() {
    try {
      const player = document.getElementById("movie_player") ||
                     document.querySelector(".html5-video-player");
      if (!player) return;

      const showingAd = player.classList.contains("ad-showing") ||
                        player.classList.contains("ad-interrupting");
      if (!showingAd) return;

      // 1) Prefer the real Skip button when it is interactable.
      const skip = document.querySelector(
        ".ytp-ad-skip-button, .ytp-ad-skip-button-modern, " +
        ".ytp-skip-ad-button, button.ytp-ad-skip-button-modern"
      );
      if (skip && skip.offsetParent !== null) {
        skip.click();
        return;
      }

      // 2) Otherwise seek the ad to its end and unmute/restore the video.
      const video = player.querySelector("video.html5-main-video") ||
                    document.querySelector("video");
      if (video && !Number.isNaN(video.duration) && video.duration > 0) {
        video.currentTime = video.duration;
        video.playbackRate = 1;
      }

      // 3) Dismiss "ad will end" overlays / closeable ad cards.
      const close = document.querySelector(
        ".ytp-ad-overlay-close-button, .ytp-ad-overlay-close-container"
      );
      if (close) close.click();
    } catch (e) {
      /* never let an exception interrupt playback */
    }
  }

  function removeAdNodes() {
    try {
      const selectors = [
        "ytd-promoted-video-renderer",
        "ytd-promoted-sparkles-web-renderer",
        "ytd-ad-slot-renderer",
        "ytd-in-feed-ad-layout-renderer",
        "ytd-banner-promo-renderer",
        "ytmusic-mealbar-promo-renderer",
        "#masthead-ad",
        ".ytp-ad-overlay-slot",
        "ytd-display-ad-renderer"
      ];
      document.querySelectorAll(selectors.join(",")).forEach((n) => n.remove());
    } catch (e) {
      /* ignore */
    }
  }

  function tick() {
    handleVideoAds();
    removeAdNodes();
  }

  // Run on every DOM mutation (catches the moment an ad starts) and on a
  // low-frequency timer as a safety net for mutations we miss.
  const observer = new MutationObserver(tick);

  function start() {
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["class"]
    });
    setInterval(tick, 500);
    tick();
  }

  if (document.documentElement) {
    start();
  } else {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  }
})();
