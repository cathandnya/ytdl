function show(enabled, useSettingsInsteadOfPreferences) {
    if (useSettingsInsteadOfPreferences) {
        document.getElementsByClassName('state-on')[0].innerText =
            "YTDLBridge’s extension is currently on. You can turn it off in the Extensions section of Safari Settings.";
        document.getElementsByClassName('state-off')[0].innerText =
            "YTDLBridge’s extension is currently off. You can turn it on in the Extensions section of Safari Settings.";
        document.getElementsByClassName('state-unknown')[0].innerText =
            "You can turn on YTDLBridge’s extension in the Extensions section of Safari Settings.";
        document.getElementsByClassName('open-preferences')[0].innerText =
            "Quit and Open Safari Settings…";
    }

    if (typeof enabled === "boolean") {
        document.body.classList.toggle("state-on", enabled);
        document.body.classList.toggle("state-off", !enabled);
    } else {
        document.body.classList.remove("state-on");
        document.body.classList.remove("state-off");
    }
}

function openPreferences() {
    webkit.messageHandlers.controller.postMessage("open-preferences");
}

document.querySelector("button.open-preferences").addEventListener("click", openPreferences);

// --- ytdl path settings -----------------------------------------------------

const pathInput = document.getElementById("ytdl-path-input");
const pathStatus = document.querySelector(".ytdl-path-status");

function setStatus(text, kind) {
    pathStatus.textContent = text;
    pathStatus.classList.toggle("ok", kind === "ok");
    pathStatus.classList.toggle("error", kind === "error");
}

/// Called from Swift once the detected/saved path is known.
/// `detected` is what the search found; `saved` is the user's override, if any.
function showYtdlPath(detected, saved, valid) {
    pathInput.value = saved || detected || "";
    pathInput.placeholder = detected || "/path/to/ytdl";

    if (!pathInput.value) {
        setStatus("ytdl was not found. Install it, or choose the file manually.", "error");
    } else if (valid) {
        setStatus(saved ? "Using your saved path." : "Detected automatically.", "ok");
    } else {
        setStatus("This path is not an executable file.", "error");
    }
}

function send(name, value) {
    webkit.messageHandlers.controller.postMessage({ name, value: value ?? "" });
}

document.querySelector("button.save").addEventListener("click", () => {
    send("save-ytdl-path", pathInput.value.trim());
});

document.querySelector("button.reset").addEventListener("click", () => {
    send("reset-ytdl-path");
});

document.querySelector("button.browse").addEventListener("click", () => {
    send("browse-ytdl-path");
});

pathInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") send("save-ytdl-path", pathInput.value.trim());
});
