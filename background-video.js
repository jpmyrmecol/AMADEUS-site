(() => {
  "use strict";

  const MIN_SIDE_MARGIN = 180;
  const MIN_VIEWPORT_HEIGHT = 650;
  const VIDEO_SRC = "/assets/amadeus_demo_web.mov";
  const MOBILE_VIDEO_SRC = "/assets/amadeus_demo_mobile.mov";

  let video = null;
  let resizeFrame = 0;
  let playbackUnavailable = false;
  let mobileDemoUnavailable = false;
  let mobileDemo = null;
  let mobileDemoVideo = null;
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  function topbarHeight() {
    const topbar = document.querySelector(".topbar");
    return topbar ? topbar.getBoundingClientRect().height : 0;
  }

  function visibleSideMargin() {
    const card = document.querySelector("main.card");
    if (card) {
      const rect = card.getBoundingClientRect();
      return Math.max(0, Math.min(rect.left, window.innerWidth - rect.right));
    }

    const layout = document.querySelector(".layout");
    if (layout) {
      const aside = layout.querySelector("aside");
      const main = layout.querySelector("main");
      if (aside && main) {
        const asideRect = aside.getBoundingClientRect();
        const mainRect = main.getBoundingClientRect();
        const left = Math.min(asideRect.left, mainRect.left);
        const right = Math.max(asideRect.right, mainRect.right);
        return Math.max(0, Math.min(left, window.innerWidth - right));
      }
    }

    return 0;
  }

  function updateTopOffset() {
    document.documentElement.style.setProperty(
      "--site-background-top",
      `${topbarHeight()}px`
    );
  }

  function hasRoomForBackgroundVideo() {
    return window.innerHeight >= MIN_VIEWPORT_HEIGHT &&
      visibleSideMargin() >= MIN_SIDE_MARGIN;
  }

  function removeVideo() {
    if (!video) return;
    video.pause();
    video.removeAttribute("src");
    video.load();
    video.remove();
    video = null;
    document.body.classList.remove("site-background-active");
  }

  function syncMobileDemo(hasBackgroundSpace) {
    if (!mobileDemo) {
      mobileDemo = document.querySelector(".site-mobile-demo");
      if (mobileDemo) {
        mobileDemoVideo = mobileDemo.querySelector("video");
        if (mobileDemoVideo) {
          mobileDemoVideo.addEventListener("error", () => {
            if (!mobileDemo.classList.contains("is-visible")) return;
            mobileDemoUnavailable = true;
            mobileDemo.classList.remove("is-visible");
            mobileDemoVideo.pause();
            mobileDemoVideo.removeAttribute("src");
            mobileDemoVideo.load();
          });
        }
      }
    }

    if (!mobileDemo || !mobileDemoVideo) return;

    const shouldShow = !hasBackgroundSpace &&
      !reducedMotion.matches &&
      !mobileDemoUnavailable;
    mobileDemo.classList.toggle("is-visible", shouldShow);

    if (shouldShow && !mobileDemoVideo.hasAttribute("src")) {
      mobileDemoVideo.autoplay = true;
      mobileDemoVideo.muted = true;
      mobileDemoVideo.defaultMuted = true;
      mobileDemoVideo.loop = true;
      mobileDemoVideo.playsInline = true;
      mobileDemoVideo.controls = false;
      mobileDemoVideo.preload = "metadata";
      mobileDemoVideo.src = MOBILE_VIDEO_SRC;
      mobileDemoVideo.load();
      const playPromise = mobileDemoVideo.play();
      if (playPromise && typeof playPromise.catch === "function") {
        playPromise.catch(() => {});
      }
    } else if (!shouldShow && mobileDemoVideo.hasAttribute("src")) {
      mobileDemoVideo.pause();
      mobileDemoVideo.removeAttribute("src");
      mobileDemoVideo.load();
    }
  }

  function addVideo() {
    if (video) return;

    video = document.createElement("video");
    video.className = "site-background-video";
    video.autoplay = true;
    video.muted = true;
    video.defaultMuted = true;
    video.loop = true;
    video.playsInline = true;
    video.preload = "metadata";
    video.setAttribute("aria-hidden", "true");
    video.setAttribute("tabindex", "-1");
    video.src = VIDEO_SRC;

    video.addEventListener("error", () => {
      playbackUnavailable = true;
      removeVideo();
    }, { once: true });

    document.body.prepend(video);
    document.body.classList.add("site-background-active");

    const playPromise = video.play();
    if (playPromise && typeof playPromise.catch === "function") {
      playPromise.catch(() => {});
    }
  }

  function syncVideo() {
    resizeFrame = 0;
    updateTopOffset();

    const hasBackgroundSpace = hasRoomForBackgroundVideo();
    if (!playbackUnavailable && !reducedMotion.matches && hasBackgroundSpace) {
      addVideo();
    } else {
      removeVideo();
    }

    syncMobileDemo(hasBackgroundSpace);
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
  reducedMotion.addEventListener("change", scheduleSync);
})();
