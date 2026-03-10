import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.Common
import qs.Modules.Plugins
import qs.Services

PluginComponent {
    id: root

    readonly property string pluginIdValue: "audioSlots"
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string appMuteScriptPath: homeDir + "/.config/DankMaterialShell/plugins/dms-audio-slots/assets/toggle-focused-mute.sh"
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    readonly property string notificationMode: pluginData.notificationMode || "toast"
    property var activeDesktopEntry: null

    function updateDesktopEntry() {
        if (activeWindow && activeWindow.appId) {
            const moddedId = Paths.moddedAppId(activeWindow.appId);
            activeDesktopEntry = DesktopEntries.heuristicLookup(moddedId);
        } else {
            activeDesktopEntry = null;
        }
    }

    Component.onCompleted: updateDesktopEntry()

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.updateDesktopEntry();
        }
    }

    Connections {
        target: root
        function onActiveWindowChanged() {
            root.updateDesktopEntry();
        }
    }

    Connections {
        target: SettingsData
        function onAppIdSubstitutionsChanged() {
            root.updateDesktopEntry();
        }
    }

    function slotNames(prefix, count) {
        const out = [];
        for (let i = 1; i <= count; i++) {
            const value = pluginData[prefix + "Slot" + i] || "";
            if (value.length > 0)
                out.push(value);
        }
        return out;
    }

    function outputCandidates() {
        const names = slotNames("output", 4);
        const nodes = Array.from(Pipewire.nodes.values).filter(node => node.audio && node.isSink && !node.isStream);
        return names.map(name => nodes.find(n => n.name === name)).filter(Boolean);
    }

    function inputCandidates() {
        const names = slotNames("input", 4);
        const nodes = Array.from(Pipewire.nodes.values).filter(node => node.audio && node.isSource && !node.isStream && !(node.name || "").endsWith(".monitor"));
        return names.map(name => nodes.find(n => n.name === name)).filter(Boolean);
    }

    function nextNode(candidates, currentName) {
        if (candidates.length === 0)
            return null;
        const idx = candidates.findIndex(node => node.name === currentName);
        return idx >= 0 ? candidates[(idx + 1) % candidates.length] : candidates[0];
    }

    function runPactl(args) {
        pactlProcess.running = false;
        pactlProcess.command = ["/usr/bin/pactl"].concat(args);
        pactlProcess.running = true;
    }

    function sendNotification(summary, body, isError) {
        const mode = notificationMode;
        if (mode === "hypr") {
            const level = isError ? "1" : "0";
            const color = isError ? "rgb(255,120,120)" : "rgb(89,146,255)";
            Quickshell.execDetached(["hyprctl", "notify", level, "2000", color, summary + ": " + body]);
            return;
        }
        if (mode === "desktop") {
            Quickshell.execDetached(["notify-send", summary, body]);
            return;
        }
        if (isError)
            ToastService.showWarning(body);
        else
            ToastService.showInfo(summary + ": " + body);
    }

    function toggleOutput() {
        const candidates = outputCandidates();
        const next = nextNode(candidates, AudioService.sink?.name || "");
        if (!next) {
            sendNotification("Audio Output", "Sinks not found. Check settings/hardware.", true);
            return;
        }
        Pipewire.preferredDefaultAudioSink = next;
        sendNotification("Audio Output", AudioService.displayName(next), false);
    }

    function toggleInput() {
        const candidates = inputCandidates();
        const currentName = AudioService.source?.name || "";
        const next = nextNode(candidates, currentName);
        if (!next) {
            sendNotification("Audio Input", "Sources not found. Check settings/hardware.", true);
            return;
        }
        try {
            Pipewire.preferredDefaultAudioSource = next;
            sendNotification("Audio Input", AudioService.displayName(next), false);
        } catch (e) {
            runPactl(["set-default-source", next.name]);
            sendNotification("Audio Input", AudioService.displayName(next), false);
        }
    }

    function runAppMute() {
        const appId = activeWindow?.appId || "";
        const title = activeWindow?.title || "";
        const appName = appId ? Paths.getAppName(appId, activeDesktopEntry) : "";
        const pid = activeWindow?.pid !== undefined ? String(activeWindow.pid) : "";
        Quickshell.execDetached(["/bin/sh", appMuteScriptPath, appId, title, appName, pid, notificationMode]);
    }

    IpcHandler {
        target: "audioOutputs"
        function toggle(): string {
            root.toggleOutput();
            return "queued";
        }
    }

    IpcHandler {
        target: "audioInputs"
        function toggle(): string {
            root.toggleInput();
            return "queued";
        }
    }

    IpcHandler {
        target: "audioAppMute"
        function toggle(): string {
            root.runAppMute();
            return "queued";
        }
    }

    Process {
        id: pactlProcess
        running: false
        command: ["/usr/bin/pactl", "info"]
    }
}
