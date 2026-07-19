// Hosts we consider "supported" — icon shows up in colour and the popup enables
// the download buttons. yt-dlp actually handles 1000+ sites, so this list is a
// UX hint rather than a hard restriction: clicks still go through if the user
// tries.
const SUPPORTED_HOST_PATTERNS = [
  /(^|\.)youtube\.com$/i,
  /^youtu\.be$/i,
  /(^|\.)youtube-nocookie\.com$/i,
  /(^|\.)vimeo\.com$/i,
  /(^|\.)nicovideo\.jp$/i,
  /(^|\.)twitter\.com$/i,
  /^x\.com$/i,
  /(^|\.)tiktok\.com$/i,
  /(^|\.)twitch\.tv$/i,
  /(^|\.)dailymotion\.com$/i,
  /(^|\.)soundcloud\.com$/i,
  /(^|\.)bilibili\.com$/i,
  /(^|\.)instagram\.com$/i,
  /(^|\.)reddit\.com$/i,
  /(^|\.)facebook\.com$/i,
];

const ICONS_ENABLED = {
  16: "icons/16.png",
  32: "icons/32.png",
  48: "icons/48.png",
  128: "icons/128.png",
};
const ICONS_DISABLED = {
  16: "icons/disabled-16.png",
  32: "icons/disabled-32.png",
  48: "icons/disabled-48.png",
  128: "icons/disabled-128.png",
};

function isSupportedUrl(url) {
  if (!url) return false;
  try {
    const u = new URL(url);
    if (u.protocol !== "http:" && u.protocol !== "https:") return false;
    return SUPPORTED_HOST_PATTERNS.some((re) => re.test(u.hostname));
  } catch {
    return false;
  }
}

async function updateActionForTab(tab) {
  if (!tab?.id) return;
  const supported = isSupportedUrl(tab.url);
  try {
    await browser.action.setIcon({
      tabId: tab.id,
      path: supported ? ICONS_ENABLED : ICONS_DISABLED,
    });
    await browser.action.setTitle({
      tabId: tab.id,
      title: supported
        ? "Download with ytdl"
        : "ytdl doesn’t recognize this site (click to try anyway)",
    });
  } catch (e) {
    console.warn("[ytdl] setIcon failed:", e);
  }
}

async function refreshActiveTab(windowId) {
  const [tab] = await browser.tabs.query({ active: true, windowId });
  if (tab) updateActionForTab(tab);
}

browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.url || changeInfo.status === "complete") {
    updateActionForTab(tab);
  }
});

browser.tabs.onActivated.addListener(async ({ tabId }) => {
  try {
    const tab = await browser.tabs.get(tabId);
    updateActionForTab(tab);
  } catch {}
});

if (browser.windows?.onFocusChanged) {
  browser.windows.onFocusChanged.addListener((windowId) => {
    if (windowId !== browser.windows.WINDOW_ID_NONE) refreshActiveTab(windowId);
  });
}

async function download(audioOnly = false) {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  if (!tab?.url) return;
  try {
    const resp = await browser.runtime.sendNativeMessage("application.id", {
      url: tab.url,
      audioOnly,
    });
    await browser.notifications.create({
      type: "basic",
      iconUrl: "icons/128.png",
      title: resp?.ok ? "ytdl started" : "ytdl failed",
      message: resp?.message ?? tab.url,
    });
  } catch (e) {
    await browser.notifications.create({
      type: "basic",
      iconUrl: "icons/128.png",
      title: "ytdl bridge error",
      message: String(e),
    });
  }
}

browser.action.onClicked.addListener(() => download(false));

if (browser.commands?.onCommand) {
  browser.commands.onCommand.addListener((command) => {
    if (command === "download-current") download(false);
  });
}

browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg?.type === "download") {
    download(Boolean(msg.audioOnly));
    return;
  }
  if (msg?.type === "queryTabSupport") {
    (async () => {
      const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
      sendResponse({ supported: isSupportedUrl(tab?.url), url: tab?.url });
    })();
    return true;
  }
});
