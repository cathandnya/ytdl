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

browser.runtime.onMessage.addListener((msg) => {
  if (msg?.type === "download") download(Boolean(msg.audioOnly));
});
