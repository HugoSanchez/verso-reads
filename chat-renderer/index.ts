import { marked } from "marked";

declare global {
  interface Window {
    VersoChatInit?: () => void;
    VersoChatAddMessage?: (id: string, role: string, content: string, isPinned?: boolean) => void;
    VersoChatAppendDelta?: (id: string, delta: string) => void;
    VersoChatFinalizeMessage?: (id: string, canPin: boolean) => void;
    VersoChatSetToolStatus?: (status: string | null) => void;
    VersoChatSetThinking?: (thinking: boolean) => void;
    VersoChatClear?: () => void;
    webkit?: {
      messageHandlers?: {
        chat?: { postMessage: (payload: Record<string, unknown>) => void };
      };
    };
  }
}

// Raw markdown buffers for streaming messages
const buffers = new Map<string, string>();

// Cache for rendered stable (completed) blocks — avoids re-parsing old content
const stableHtmlCache = new Map<string, string>();
const stableTextCache = new Map<string, string>();

// Pending render state — debounce rapid deltas (~80ms) to avoid DOM thrashing
const dirtyIds = new Set<string>();
let debounceTimer: ReturnType<typeof setTimeout> | null = null;

const postMessage = (payload: Record<string, unknown>) => {
  if (window.webkit?.messageHandlers?.chat) {
    window.webkit.messageHandlers.chat.postMessage(payload);
  }
};

// Configure marked for clean output
marked.setOptions({
  breaks: false,
  gfm: true,
});

function getContainer(): HTMLElement {
  return document.getElementById("chat-container")!;
}

function scrollToBottom() {
  window.scrollTo({ top: document.body.scrollHeight, behavior: "instant" });
}

function renderMarkdown(text: string): string {
  if (!text || text.trim() === "") return "";
  return marked.parse(text, { async: false }) as string;
}

function splitStableTail(text: string): [string, string] {
  // Find the last double-newline boundary — everything before it is "stable"
  // (complete blocks that won't change), everything after is the in-progress tail
  const lastBreak = text.lastIndexOf("\n\n");
  if (lastBreak === -1) return ["", text];
  return [text.slice(0, lastBreak + 2), text.slice(lastBreak + 2)];
}

function flushDirty() {
  for (const id of dirtyIds) {
    const buffer = buffers.get(id);
    if (!buffer) continue;

    const wrapper = getContainer().querySelector(
      `[data-id="${id}"]`
    ) as HTMLElement | null;
    if (!wrapper) continue;

    const contentDiv = wrapper.querySelector(".message-content") as HTMLElement;
    if (!contentDiv) continue;

    const [stableText, tail] = splitStableTail(buffer);

    // Only re-render stable portion if it grew since last time
    const prevStable = stableTextCache.get(id) ?? "";
    if (stableText !== prevStable) {
      stableHtmlCache.set(id, renderMarkdown(stableText));
      stableTextCache.set(id, stableText);
    }

    const stableHtml = stableHtmlCache.get(id) ?? "";

    // Stable blocks as rendered HTML + tail as plain text span
    if (tail) {
      const escapedTail = tail
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
      contentDiv.innerHTML =
        stableHtml + `<span class="streaming-tail">${escapedTail}</span>`;
    } else {
      contentDiv.innerHTML = stableHtml;
    }
  }
  dirtyIds.clear();
  scrollToBottom();
}

function scheduleDirtyRender(id: string) {
  dirtyIds.add(id);
  if (debounceTimer === null) {
    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      requestAnimationFrame(flushDirty);
    }, 80);
  }
}

function createMessageElement(
  id: string,
  role: string,
  content: string
): HTMLElement {
  const wrapper = document.createElement("div");
  wrapper.className = `message message-${role}`;
  wrapper.setAttribute("data-id", id);

  const contentDiv = document.createElement("div");
  contentDiv.className = "message-content";

  if (role === "assistant") {
    contentDiv.innerHTML = renderMarkdown(content);
  } else {
    contentDiv.textContent = content;
  }

  wrapper.appendChild(contentDiv);
  return wrapper;
}

// -- Unified activity indicator (dots or tool status, same element, same place) --

function getOrCreateIndicator(): HTMLElement {
  let el = document.getElementById("activity-indicator");
  if (!el) {
    el = document.createElement("div");
    el.id = "activity-indicator";
    el.className = "message message-assistant";
    el.style.display = "none";

    const inner = document.createElement("div");
    inner.className = "activity-inner";
    el.appendChild(inner);

    getContainer().appendChild(el);
  }
  return el;
}

function showIndicatorDots() {
  const el = getOrCreateIndicator();
  const inner = el.querySelector(".activity-inner")!;
  inner.innerHTML = '<div class="thinking-dots"><div class="dot"></div><div class="dot"></div><div class="dot"></div></div>';
  el.style.display = "";
  // Keep it at the end of the container
  const container = getContainer();
  if (el.parentElement !== container || el !== container.lastElementChild) {
    container.appendChild(el);
  }
  scrollToBottom();
}

function showIndicatorText(text: string) {
  const el = getOrCreateIndicator();
  const inner = el.querySelector(".activity-inner")!;
  inner.innerHTML = `<span class="tool-status-text">${text}</span>`;
  el.style.display = "";
  const container = getContainer();
  if (el.parentElement !== container || el !== container.lastElementChild) {
    container.appendChild(el);
  }
  scrollToBottom();
}

function hideIndicator() {
  const el = document.getElementById("activity-indicator");
  if (el) el.style.display = "none";
}

let isThinking = false;
let hasReceivedContent = false;

// -- Public API --

window.VersoChatInit = () => {
  postMessage({ type: "ready" });
};

window.VersoChatAddMessage = (id: string, role: string, content: string, isPinned?: boolean) => {
  const container = getContainer();

  // Remove empty state if present
  const emptyState = container.querySelector(".empty-state");
  if (emptyState) emptyState.remove();

  // Don't add if already exists
  if (container.querySelector(`[data-id="${id}"]`)) return;

  const el = createMessageElement(id, role, content);

  // Add pinned badge for pinned messages
  if (isPinned) {
    el.classList.add("message-pinned");
    // Add badge to the first pinned message (user question)
    if (role === "user") {
      const badge = document.createElement("div");
      badge.className = "pin-badge";
      badge.innerHTML = `<span class="pin-badge-dot"></span> Pinned`;
      const dismiss = document.createElement("span");
      dismiss.className = "pin-badge-dismiss";
      dismiss.textContent = "×";
      dismiss.addEventListener("click", (e) => {
        e.stopPropagation();
        postMessage({ type: "dismiss-pin" });
      });
      badge.appendChild(dismiss);
      el.insertBefore(badge, el.firstChild);
    }
  }

  container.appendChild(el);
  scrollToBottom();
};

window.VersoChatAppendDelta = (id: string, delta: string) => {
  const current = buffers.get(id) ?? "";
  const updated = current + delta;
  buffers.set(id, updated);

  // First delta arrived — hide indicator, stop showing dots/tool for this turn
  if (!current) {
    hasReceivedContent = true;
    hideIndicator();
  }

  let wrapper = getContainer().querySelector(
    `[data-id="${id}"]`
  ) as HTMLElement | null;
  if (!wrapper) {
    wrapper = createMessageElement(id, "assistant", "");
    getContainer().appendChild(wrapper);
  }

  // Coalesce into next animation frame instead of rendering immediately
  scheduleDirtyRender(id);
};

window.VersoChatFinalizeMessage = (id: string, canPin: boolean) => {
  const buffer = buffers.get(id);
  if (buffer) {
    const wrapper = getContainer().querySelector(
      `[data-id="${id}"]`
    ) as HTMLElement | null;
    if (wrapper) {
      const contentDiv = wrapper.querySelector(
        ".message-content"
      ) as HTMLElement;
      if (contentDiv) {
        contentDiv.innerHTML = renderMarkdown(buffer);
      }

      // Add pin button if applicable
      if (canPin && !wrapper.querySelector(".pin-btn")) {
        const pinBtn = document.createElement("div");
        pinBtn.className = "pin-btn";
        pinBtn.innerHTML = `<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 17v5"/><path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/></svg> Pin answer`;
        pinBtn.addEventListener("click", () => {
          postMessage({ type: "pin-click", messageId: id });
        });
        wrapper.appendChild(pinBtn);
      }
    }
    buffers.delete(id);
    stableHtmlCache.delete(id);
    stableTextCache.delete(id);
  }

  // Clean up from dirty set
  dirtyIds.delete(id);

  // Hide activity indicator when done
  hideIndicator();

  scrollToBottom();
};

window.VersoChatSetToolStatus = (status: string | null) => {
  if (hasReceivedContent) return;
  if (status) {
    showIndicatorText(status);
  } else if (isThinking) {
    showIndicatorDots();
  } else {
    hideIndicator();
  }
};

window.VersoChatSetThinking = (thinking: boolean) => {
  isThinking = thinking;
  if (thinking) {
    hasReceivedContent = false;
    showIndicatorDots();
  } else {
    hasReceivedContent = false;
    hideIndicator();
  }
};

window.VersoChatClear = () => {
  getContainer().innerHTML = "";
  buffers.clear();
  dirtyIds.clear();
  stableHtmlCache.clear();
  stableTextCache.clear();
};
