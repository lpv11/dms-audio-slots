import QtQuick
import Quickshell.Services.Pipewire
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "audioSlots"

    property var outputDevices: []
    property var inputDevices: []
    readonly property var disabledOption: ({label: "Disabled", value: ""})
    readonly property var emptyOption: [disabledOption]

    function sortByLabel(items) {
        return items.sort((a, b) => a.label.localeCompare(b.label));
    }

    function toOption(node) {
        return {label: AudioService.displayName(node), value: node.name};
    }

    function uniqueByValue(items) {
        const seen = {};
        const out = [];
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            if (!item.value || seen[item.value])
                continue;
            seen[item.value] = true;
            out.push(item);
        }
        return out;
    }

    function refreshDevices() {
        const allNodes = Array.from(Pipewire.nodes.values);
        const outputs = allNodes.filter(node => node.audio && node.isSink && !node.isStream).map(toOption);
        const inputs = allNodes.filter(node => node.audio && !node.isSink && !node.isStream && !(node.name || "").endsWith(".monitor")).map(toOption);

        const sortedOutputs = sortByLabel(uniqueByValue(outputs));
        const sortedInputs = sortByLabel(uniqueByValue(inputs));

        root.outputDevices = sortedOutputs.concat([root.disabledOption]);
        root.inputDevices = sortedInputs.concat([root.disabledOption]);
    }

    function slotDefault(devices, savedValue, fallbackIndex) {
        if (savedValue && savedValue.length > 0)
            return savedValue;
        const realDevices = devices.filter(d => d.value && d.value.length > 0);
        if (realDevices.length > fallbackIndex)
            return realDevices[fallbackIndex].value;
        if (realDevices.length > 0)
            return realDevices[0].value;
        return "";
    }

    Component.onCompleted: refreshDevices()

    Connections {
        target: Pipewire.nodes
        function onValuesChanged() {
            root.refreshDevices();
        }
    }

    StyledText {
        width: parent.width
        text: "Audio Slots IPC"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Save four output slots and four input slots from live Pipewire device discovery. IPC commands cycle only through saved devices that are currently connected."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    DankButton {
        text: "Refresh Device Lists"
        iconName: "refresh"
        onClicked: root.refreshDevices()
    }

    SelectionSetting {
        settingKey: "notificationMode"
        label: "Notification backend"
        options: [
            {label: "DMS toast", value: "toast"},
            {label: "Desktop notify-send", value: "desktop"},
            {label: "Hyprland (hyprctl notify)", value: "hypr"}
        ]
        defaultValue: pluginData.notificationMode || "toast"
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
    }

    StyledText {
        text: "Outputs"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    SelectionSetting {
        settingKey: "outputSlot1"
        label: "Output slot 1"
        options: root.outputDevices.length ? root.outputDevices : root.emptyOption
        defaultValue: root.slotDefault(root.outputDevices, pluginData.outputSlot1 || "", 0)
    }

    SelectionSetting {
        settingKey: "outputSlot2"
        label: "Output slot 2"
        options: root.outputDevices.length ? root.outputDevices : root.emptyOption
        defaultValue: root.slotDefault(root.outputDevices, pluginData.outputSlot2 || "", 1)
    }

    SelectionSetting {
        settingKey: "outputSlot3"
        label: "Output slot 3"
        options: root.outputDevices.length ? root.outputDevices : root.emptyOption
        defaultValue: root.slotDefault(root.outputDevices, pluginData.outputSlot3 || "", 2)
    }

    SelectionSetting {
        settingKey: "outputSlot4"
        label: "Output slot 4"
        options: root.outputDevices.length ? root.outputDevices : root.emptyOption
        defaultValue: root.slotDefault(root.outputDevices, pluginData.outputSlot4 || "", 3)
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
    }

    StyledText {
        text: "Inputs"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    SelectionSetting {
        settingKey: "inputSlot1"
        label: "Input slot 1"
        options: root.inputDevices.length ? root.inputDevices : root.emptyOption
        defaultValue: root.slotDefault(root.inputDevices, pluginData.inputSlot1 || "", 0)
    }

    SelectionSetting {
        settingKey: "inputSlot2"
        label: "Input slot 2"
        options: root.inputDevices.length ? root.inputDevices : root.emptyOption
        defaultValue: root.slotDefault(root.inputDevices, pluginData.inputSlot2 || "", 1)
    }

    SelectionSetting {
        settingKey: "inputSlot3"
        label: "Input slot 3"
        options: root.inputDevices.length ? root.inputDevices : root.emptyOption
        defaultValue: root.slotDefault(root.inputDevices, pluginData.inputSlot3 || "", 2)
    }

    SelectionSetting {
        settingKey: "inputSlot4"
        label: "Input slot 4"
        options: root.inputDevices.length ? root.inputDevices : root.emptyOption
        defaultValue: root.slotDefault(root.inputDevices, pluginData.inputSlot4 || "", 3)
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "This plugin runs as a daemon. Control it through IPC commands only."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    StyledText {
        text: "IPC Commands"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    StyledRect {
        width: parent.width
        height: commandsCol.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: commandsCol
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: "dms ipc audioOutputs toggle"
                font.pixelSize: Theme.fontSizeMedium
                font.family: "monospace"
                color: Theme.surfaceText
                wrapMode: Text.WrapAnywhere
            }

            StyledText {
                width: parent.width
                text: "dms ipc audioInputs toggle"
                font.pixelSize: Theme.fontSizeMedium
                font.family: "monospace"
                color: Theme.surfaceText
                wrapMode: Text.WrapAnywhere
            }

            StyledText {
                width: parent.width
                text: "dms ipc audioAppMute toggle"
                font.pixelSize: Theme.fontSizeMedium
                font.family: "monospace"
                color: Theme.surfaceText
                wrapMode: Text.WrapAnywhere
            }
        }
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Use those exact commands in terminal, keybind scripts, or automation."
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceVariantText
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Because this is a daemon plugin, no bar widget placement is required for IPC targets to exist."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Set Notification backend to Hyprland to restore hyprctl-style notifications."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
