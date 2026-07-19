async function send(audioOnly) {
  try {
    await browser.runtime.sendMessage({ type: "download", audioOnly });
  } catch (e) {
    console.error("[ytdl popup] sendMessage failed:", e);
  }
  window.close();
}

document.getElementById("video").addEventListener("click", () => send(false));
document.getElementById("audio").addEventListener("click", () => send(true));
