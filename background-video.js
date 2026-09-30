(() => {
  "use strict";

  const MIN_SIDE_MARGIN = 100;
  const MIN_VIEWPORT_HEIGHT = 650;
  const BACKGROUND_VIDEO_ASPECT_RATIO = 1920 / 840;
  const MIN_VISIBLE_BACKGROUND_WIDTH = 0.70;
  const VIDEO_SRC = "/assets/amadeus_demo_web.mp4";
  const MOBILE_VIDEO_SRC = "/assets/amadeus_demo_mobile.mp4";
  const VIDEO_POSTER_SRC = "/assets/amadeus_demo_web_poster.webp";
  const MOBILE_VIDEO_POSTER_SRC = "/assets/amadeus_demo_mobile_poster.webp";

  let video = null;
  let poster = null;
  let desktopControl = null;
  let desktopHitArea = null;
  let resizeFrame = 0;
  let playbackUnavailable = false;
  let desktopManualPlayback = false;
  let desktopAutoplayFallback = false;

  let mobileDemoUnavailable = false;
  let mobileDemo = null;
  let mobileDemoVideo = null;
  let mobileControl = null;
  let mobileManualPlayback = false;
  let mobileAutoplayFallback = false;

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  function topbarHeight() {
    const topbar = document.querySelector(".topbar");
    return topbar ? topbar.getBoundingClientRect().height : 0;
  }

  function contentRect() {
    const card = document.querySelector("main.card");
    if (card) {
      return card.getBoundingClientRect();
    }

    const layout = document.querySelector(".layout");
    if (layout) {
      const aside = layout.querySelector("aside");
      const main = layout.querySelector("main");
      if (aside && main) {
        const asideRect = aside.getBoundingClientRect();
        const mainRect = main.getBoundingClientRect();
        return {
          left: Math.min(asideRect.left, mainRect.left),
          right: Math.max(asideRect.right, mainRect.right)
        };
      }
    }

    return null;
  }

  function visibleSideMargin() {
    const rect = contentRect();
    if (!rect) return 0;
    return Math.max(0, Math.min(rect.left, window.innerWidth - rect.right));
  }

  function updateTopOffset() {
    document.documentElement.style.setProperty(
      "--site-background-top",
      topbarHeight() + "px"
    );
  }

  function hasRoomForBackgroundVideo() {
    const backgroundHeight = Math.max(1, window.innerHeight - topbarHeight());
    const viewportAspectRatio = window.innerWidth / backgroundHeight;
    const visibleBackgroundWidth = Math.min(
      1,
      viewportAspectRatio / BACKGROUND_VIDEO_ASPECT_RATIO
    );

    return window.innerHeight >= MIN_VIEWPORT_HEIGHT &&
      visibleSideMargin() >= MIN_SIDE_MARGIN &&
      visibleBackgroundWidth >= MIN_VISIBLE_BACKGROUND_WIDTH;
  }

  function refreshBackgroundActive() {
    document.body.classList.toggle(
      "site-background-active",
      Boolean(video || poster)
    );
  }

  function setControlState(control, isPlaying) {
    if (!control) return;
    control.classList.toggle("is-hidden", isPlaying);
  }

  function createControl(extraClass) {
    const control = document.createElement("span");
    control.className = "site-demo-control " + extraClass;
    control.setAttribute("aria-hidden", "true");
    control.innerHTML =
      '<span class="site-demo-control__disc">' +
      '<span class="site-demo-control__icon"></span>' +
      "</span>";
    return control;
  }

  function removeBackgroundVideo() {
    if (!video) return;
    video.pause();
    video.removeAttribute("src");
    video.load();
    video.remove();
    video = null;
    refreshBackgroundActive();
  }

  function removeBackgroundPoster() {
    if (!poster) return;
    poster.remove();
    poster = null;
    refreshBackgroundActive();
  }

  function removeDesktopControl() {
    if (!desktopControl) return;
    desktopControl.remove();
    desktopControl = null;
  }

  function removeDesktopHitArea() {
    if (!desktopHitArea) return;
    desktopHitArea.remove();
    desktopHitArea = null;
  }

  function addBackgroundPoster() {
    if (poster) return;
    poster = document.createElement("img");
    poster.className = "site-background-poster";
    poster.src = VIDEO_POSTER_SRC;
    poster.alt = "";
    poster.setAttribute("aria-hidden", "true");
    document.body.prepend(poster);
    refreshBackgroundActive();
  }

  function positionDesktopControl() {
    if (!desktopControl) return;

    const rect = contentRect();
    if (!rect) return;

    const rightMargin = Math.max(0, window.innerWidth - rect.right);
    const x = rect.right + rightMargin / 2;
    const availableHeight = Math.max(0, window.innerHeight - topbarHeight());
    const y = topbarHeight() + availableHeight / 2;

    desktopControl.style.left = Math.round(x) + "px";
    desktopControl.style.top = Math.round(y) + "px";
  }

  function createBackgroundVideo(autoplay) {
    if (video) return video;

    video = document.createElement("video");
    video.className = "site-background-video";
    video.autoplay = autoplay;
    video.muted = true;
    video.defaultMuted = true;
    video.loop = true;
    video.playsInline = true;
    video.preload = autoplay ? "metadata" : "auto";
    video.setAttribute("aria-hidden", "true");
    video.setAttribute("tabindex", "-1");
    video.src = VIDEO_SRC;

    video.addEventListener("play", () => {
      setControlState(desktopControl, true);
      if (desktopHitArea) {
        desktopHitArea.setAttribute("aria-label", "Pause demo video");
      }
    });
    video.addEventListener("pause", () => {
      setControlState(desktopControl, false);
      if (desktopHitArea) {
        desktopHitArea.setAttribute("aria-label", "Play demo video");
      }
    });
    video.addEventListener("error", () => {
      playbackUnavailable = true;
      desktopManualPlayback = false;
      removeBackgroundVideo();
      setControlState(desktopControl, true);
      if (desktopHitArea) {
        desktopHitArea.disabled = true;
        desktopHitArea.setAttribute("aria-label", "Demo video unavailable");
      }
    }, { once: true });

    if (poster) {
      poster.after(video);
    } else {
      document.body.prepend(video);
    }
    refreshBackgroundActive();

    return video;
  }

  function toggleDesktopPlayback() {
    if (playbackUnavailable) return;

    desktopManualPlayback = true;
    const target = createBackgroundVideo(false);

    if (target.paused) {
      const playPromise = target.play();
      if (playPromise && typeof playPromise.catch === "function") {
        playPromise.catch(() => {
          setControlState(desktopControl, false);
        });
      }
    } else {
      target.pause();
    }
  }

  function ensureDesktopInteraction() {
    if (!desktopHitArea) {
      desktopHitArea = document.createElement("button");
      desktopHitArea.type = "button";
      desktopHitArea.className = "site-background-hitarea";
      desktopHitArea.setAttribute("aria-label", "Play demo video");
      desktopHitArea.addEventListener("click", toggleDesktopPlayback);
      document.body.append(desktopHitArea);
    }

    if (!desktopControl) {
      desktopControl = createControl("site-demo-control--background");
      document.body.append(desktopControl);
    }

    positionDesktopControl();

    const isPlaying = Boolean(video && !video.paused);
    setControlState(desktopControl, isPlaying);
    desktopHitArea.disabled = playbackUnavailable;
    desktopHitArea.setAttribute(
      "aria-label",
      playbackUnavailable
        ? "Demo video unavailable"
        : isPlaying
          ? "Pause demo video"
          : "Play demo video"
    );
  }

  function ensureMobileElements() {
    if (mobileDemo) return;

    mobileDemo = document.querySelector(".site-mobile-demo");
    if (!mobileDemo) return;

    mobileDemoVideo = mobileDemo.querySelector("video");
    if (!mobileDemoVideo) return;

    mobileDemo.addEventListener("click", () => {
      if (mobileDemo.classList.contains("is-manual-playback")) {
        toggleMobilePlayback();
      }
    });

    mobileDemo.addEventListener("keydown", (event) => {
      if (!mobileDemo.classList.contains("is-manual-playback")) {
        return;
      }
      if (event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
      toggleMobilePlayback();
    });

    mobileDemoVideo.addEventListener("play", () => {
      setControlState(mobileControl, true);
      mobileDemo.setAttribute("aria-label", "Pause demo video");
    });
    mobileDemoVideo.addEventListener("pause", () => {
      setControlState(mobileControl, false);
      mobileDemo.setAttribute("aria-label", "Play demo video");
    });
    mobileDemoVideo.addEventListener("error", () => {
      if (!mobileDemo.classList.contains("is-visible")) return;
      mobileDemoUnavailable = true;
      mobileManualPlayback = false;
      mobileDemoVideo.pause();
      mobileDemoVideo.removeAttribute("src");
      mobileDemoVideo.load();

      if (reducedMotion.matches || mobileAutoplayFallback) {
        mobileDemoVideo.poster = MOBILE_VIDEO_POSTER_SRC;
        setControlState(mobileControl, true);
        mobileDemo.removeAttribute("role");
        mobileDemo.removeAttribute("tabindex");
        mobileDemo.setAttribute("aria-label", "Demo video unavailable");
      } else {
        mobileDemo.classList.remove("is-visible");
      }
    });
  }

  function removeMobileControl() {
    if (!mobileControl) return;
    mobileControl.remove();
    mobileControl = null;
  }

  function toggleMobilePlayback() {
    if (!mobileDemoVideo || mobileDemoUnavailable) return;

    mobileManualPlayback = true;

    if (!mobileDemoVideo.hasAttribute("src")) {
      mobileDemoVideo.preload = "auto";
      mobileDemoVideo.src = MOBILE_VIDEO_SRC;
      mobileDemoVideo.load();
    }

    if (mobileDemoVideo.paused) {
      const playPromise = mobileDemoVideo.play();
      if (playPromise && typeof playPromise.catch === "function") {
        playPromise.catch(() => {
          setControlState(mobileControl, false);
        });
      }
    } else {
      mobileDemoVideo.pause();
    }
  }

  function ensureMobileControl() {
    if (!mobileDemo || !mobileDemoVideo) return;

    if (!mobileControl) {
      mobileControl = createControl("site-demo-control--mobile");
      mobileDemo.append(mobileControl);
    }

    setControlState(
      mobileControl,
      Boolean(mobileDemoVideo.hasAttribute("src") && !mobileDemoVideo.paused)
    );
  }

  function hideMobileDemo() {
    if (!mobileDemo || !mobileDemoVideo) return;

    mobileDemo.classList.remove("is-visible", "is-manual-playback");
    mobileDemo.removeAttribute("role");
    mobileDemo.removeAttribute("tabindex");
    mobileDemo.removeAttribute("aria-label");
    removeMobileControl();
    mobileManualPlayback = false;

    mobileDemoVideo.pause();
    mobileDemoVideo.removeAttribute("src");
    mobileDemoVideo.removeAttribute("poster");
    mobileDemoVideo.preload = "metadata";
    mobileDemoVideo.load();
  }

  function showManualMobileDemo() {
    if (!mobileDemo || !mobileDemoVideo) return;

    mobileDemo.classList.add("is-visible", "is-manual-playback");
    mobileDemo.setAttribute("role", "button");
    mobileDemo.setAttribute("tabindex", "0");

    mobileDemoVideo.autoplay = false;
    mobileDemoVideo.muted = true;
    mobileDemoVideo.defaultMuted = true;
    mobileDemoVideo.loop = true;
    mobileDemoVideo.playsInline = true;
    mobileDemoVideo.controls = false;
    mobileDemoVideo.poster = MOBILE_VIDEO_POSTER_SRC;

    if (!mobileManualPlayback) {
      mobileDemoVideo.pause();
      if (mobileDemoVideo.hasAttribute("src")) {
        mobileDemoVideo.removeAttribute("src");
        mobileDemoVideo.load();
      }
      mobileDemoVideo.preload = "none";
    }

    ensureMobileControl();

    const isPlaying = Boolean(
      mobileDemoVideo.hasAttribute("src") && !mobileDemoVideo.paused
    );
    mobileDemo.setAttribute(
      "aria-label",
      isPlaying ? "Pause demo video" : "Play demo video"
    );
  }

  function showAutoplayMobileDemo() {
    if (!mobileDemo || !mobileDemoVideo) return;

    mobileDemo.classList.add("is-visible");
    mobileDemo.classList.remove("is-manual-playback");
    mobileDemo.removeAttribute("role");
    mobileDemo.removeAttribute("tabindex");
    mobileDemo.removeAttribute("aria-label");
    removeMobileControl();
    mobileManualPlayback = false;

    mobileDemoVideo.autoplay = true;
    mobileDemoVideo.muted = true;
    mobileDemoVideo.defaultMuted = true;
    mobileDemoVideo.loop = true;
    mobileDemoVideo.playsInline = true;
    mobileDemoVideo.controls = false;
    mobileDemoVideo.preload = "metadata";
    mobileDemoVideo.removeAttribute("poster");

    if (!mobileDemoVideo.hasAttribute("src")) {
      mobileDemoVideo.src = MOBILE_VIDEO_SRC;
      mobileDemoVideo.load();
    }

    const playPromise = mobileDemoVideo.play();
    if (playPromise && typeof playPromise.catch === "function") {
      playPromise.catch(() => {
        if (reducedMotion.matches ||
            hasRoomForBackgroundVideo() ||
            !mobileDemo.classList.contains("is-visible")) {
          return;
        }

        mobileAutoplayFallback = true;
        mobileManualPlayback = false;
        showManualMobileDemo();
      });
    }
  }

  function syncMobileDemo(hasBackgroundSpace) {
    ensureMobileElements();
    if (!mobileDemo || !mobileDemoVideo) return;

    const shouldShow = !hasBackgroundSpace && !mobileDemoUnavailable;
    if (!shouldShow) {
      hideMobileDemo();
      return;
    }

    if (reducedMotion.matches || mobileAutoplayFallback) {
      showManualMobileDemo();
    } else {
      showAutoplayMobileDemo();
    }
  }

  function syncDesktopBackground(hasBackgroundSpace) {
    if (!hasBackgroundSpace) {
      desktopManualPlayback = false;
      removeBackgroundVideo();
      removeBackgroundPoster();
      removeDesktopControl();
      removeDesktopHitArea();
      return;
    }

    if (reducedMotion.matches || desktopAutoplayFallback) {
      addBackgroundPoster();
      ensureDesktopInteraction();

      if (!desktopManualPlayback) {
        removeBackgroundVideo();
      }
      return;
    }

    desktopManualPlayback = false;
    removeBackgroundPoster();
    removeDesktopControl();
    removeDesktopHitArea();

    if (!playbackUnavailable) {
      const target = createBackgroundVideo(true);
      const playPromise = target.play();
      if (playPromise && typeof playPromise.catch === "function") {
        playPromise.catch(() => {
          if (video !== target ||
              reducedMotion.matches ||
              !hasRoomForBackgroundVideo()) {
            return;
          }

          desktopAutoplayFallback = true;
          desktopManualPlayback = false;
          removeBackgroundVideo();
          addBackgroundPoster();
          ensureDesktopInteraction();
        });
      }
    } else {
      removeBackgroundVideo();
    }
  }

  function syncVideo() {
    resizeFrame = 0;
    updateTopOffset();

    const hasBackgroundSpace = hasRoomForBackgroundVideo();
    syncDesktopBackground(hasBackgroundSpace);
    syncMobileDemo(hasBackgroundSpace);

    if (desktopControl) {
      positionDesktopControl();
    }
  }

  function resetForMotionPreferenceChange() {
    desktopManualPlayback = false;
    mobileManualPlayback = false;
    removeBackgroundVideo();
    removeBackgroundPoster();
    removeDesktopControl();
    removeDesktopHitArea();

    ensureMobileElements();
    if (mobileDemoVideo) {
      mobileDemoVideo.pause();
      mobileDemoVideo.removeAttribute("src");
      mobileDemoVideo.removeAttribute("poster");
      mobileDemoVideo.load();
    }
    if (mobileDemo) {
      mobileDemo.removeAttribute("role");
      mobileDemo.removeAttribute("tabindex");
      mobileDemo.removeAttribute("aria-label");
    }
    removeMobileControl();

    syncVideo();
  }

  function scheduleSync() {
    if (resizeFrame) return;
    resizeFrame = window.requestAnimationFrame(syncVideo);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", syncVideo, { once: true });
  } else {
    syncVideo();
  }

  window.addEventListener("load", scheduleSync, { once: true });
  window.addEventListener("resize", scheduleSync, { passive: true });
  reducedMotion.addEventListener("change", resetForMotionPreferenceChange);
})();
