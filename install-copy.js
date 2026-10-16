/* Add copy actions only to standalone command blocks in Manual section 1. */
(() => {
  "use strict";

  const japanese = document.documentElement.lang.toLowerCase().startsWith("ja");
  const labels = japanese
    ? { copy: "コピー", copied: "コピーしました", failed: "コピーできませんでした" }
    : { copy: "Copy", copied: "Copied", failed: "Copy failed" };

  function legacyCopy(text) {
    const field = document.createElement("textarea");
    field.value = text;
    field.readOnly = true;
    field.setAttribute("aria-hidden", "true");
    field.style.cssText = "position:fixed;left:-9999px;top:0;opacity:0;";
    document.body.appendChild(field);
    field.focus();
    field.select();
    try {
      return document.execCommand("copy");
    } catch (_) {
      return false;
    } finally {
      field.remove();
    }
  }

  async function copyCommand(text) {
    if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch (_) {
        // Fallback for browsers or contexts with restricted clipboard access.
      }
    }
    return legacyCopy(text);
  }

  function addCopyButtons() {
    // <code> in paragraphs is intentionally excluded (e.g. "amadeus").
    const section = document.getElementById('section-1')?.closest('section');
    if (!section) return;
    section.querySelectorAll('pre > code').forEach((code) => {
      const pre = code.parentElement;
      if (!pre || pre.parentElement.classList.contains("manual-command-block")) return;
      if (!code.textContent.trim()) return;

      const wrapper = document.createElement("div");
      wrapper.className = "manual-command-block";
      pre.before(wrapper);
      wrapper.appendChild(pre);

      const button = document.createElement("button");
      button.type = "button";
      button.className = "manual-command-copy";
      button.textContent = labels.copy;
      button.setAttribute("aria-label", labels.copy);
      button.setAttribute("aria-live", "polite");
      wrapper.appendChild(button);

      button.addEventListener("click", async () => {
        if (button.disabled) return;
        button.disabled = true;
        const copied = await copyCommand(code.textContent.trim());
        if (!copied) {
          const selection = window.getSelection();
          if (selection) {
            const range = document.createRange();
            range.selectNodeContents(code);
            selection.removeAllRanges();
            selection.addRange(range);
          }
        }
        button.textContent = copied ? labels.copied : labels.failed;
        button.setAttribute("aria-label", button.textContent);
        window.setTimeout(() => {
          button.textContent = labels.copy;
          button.setAttribute("aria-label", labels.copy);
          button.disabled = false;
        }, 1800);
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", addCopyButtons, { once: true });
  } else {
    addCopyButtons();
  }
})();
