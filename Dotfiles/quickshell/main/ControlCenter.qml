import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: ccScope

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: root
            required property var modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

            property bool ready: false
            property bool isClosing: false
            property bool ccHeld: false

            // ══════════════════════════════════════════════════
            //  THEME
            // ══════════════════════════════════════════════════
            property color bgColor:          "#0a0a0a"
            property color bgColorAlt:       "#0d0d0d"
            property color fgColor:          "#ffffff"
            property color accentBlue:       "#89b4fa"
            property color accentPurple:     "#cba6f7"
            property color accentRed:        "#f38ba8"
            property color borderColor:      Qt.rgba(1, 1, 1, 0.08)
            property real  cornerRadius:     14
            property real  panelRadius:      18
            property real  animDuration:     250
            property real  toggleSize:       34
            property real  toggleHeight:     19
            property real  toggleRadius:     9.5

            // ── WiFi state ──
            property bool   wifiEnabled:      false
            property bool   wifiConnected:    false
            property string wifiSSID:         ""
            property int    wifiSignal:       0
            property bool   wifiScanning:     false
            property var    wifiNetworks:     []
            property string wifiPasswordSSID: ""
            property bool   wifiConnecting:   false

            // ── Bluetooth state ──
            property bool   btEnabled:          false
            property bool   btConnected:        false
            property bool   btScanning:         false
            property var    btPairedDevices:    []
            property var    btAvailableDevices: []
            property string btConnectingMAC:    ""

            // ── Battery state ──
            property int    batteryPercent:  0
            property bool   batteryCharging: false
            property string batteryTime:     ""
            property string batteryClass:    ""

            // ── Layout ──
            readonly property int panelW: 375
            readonly property int panelY: -5
            readonly property int panelH: 175

            property real cardX: GlobalStates.controlCenterOpen
                ? root.width - root.panelW
                : (root.ccHeld ? root.width - 360 : root.width + 20)

            Behavior on cardX {
                enabled: root.ready
                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
            }

            Component.onCompleted: { readyTimer.start(); pollAll() }

            // ══════════════════════════════════════════════════
            //  FUNCTIONS  (mirrored from reference shell.qml)
            // ══════════════════════════════════════════════════

            function pollAll() {
                if (!wifiStatusProc.running)   wifiStatusProc.running   = true
                if (!wifiCurrentProc.running)  wifiCurrentProc.running  = true
                if (!btStatusProc.running)     btStatusProc.running     = true
                if (!batteryProc.running)      batteryProc.running      = true
            }

            // Refresh wifi — matches reference refreshWifi()
            function refreshWifi() {
                root.wifiNetworks  = []
                root.wifiScanning  = true
                if (!wifiStatusProc.running)  wifiStatusProc.running  = true
                if (!wifiCurrentProc.running) wifiCurrentProc.running = true
                if (!wifiScanProc.running)    wifiScanProc.running    = true
            }

            // Refresh bluetooth — matches reference refreshBluetooth()
            function refreshBluetooth() {
                root.btPairedDevices    = []
                root.btAvailableDevices = []
                root.btScanning         = false
                root.btConnectingMAC    = ""
                if (!btStatusProc.running) btStatusProc.running = true
            }

            // BT helpers — exact commands from reference shell.qml
            function connectBt(mac) {
                root.btConnectingMAC = mac
                btActionProc.command = ["bash", "-c",
                    "(echo 'trust " + mac + "'; echo 'connect " + mac + "'; sleep 2; echo 'quit') | bluetoothctl 2>/dev/null"]
                btActionProc.running = true
            }

            function disconnectBt(mac) {
                btActionProc.command = ["bash", "-c",
                    "echo -e 'disconnect " + mac + "\\nquit' | bluetoothctl 2>/dev/null"]
                btActionProc.running = true
            }

            function pairBt(mac) {
                root.btConnectingMAC = mac
                btActionProc.command = ["bash", "-c",
                    "echo -e 'pair " + mac + "\\nquit' | bluetoothctl 2>/dev/null; " +
                    "sleep 2; " +
                    "echo -e 'trust " + mac + "\\nquit' | bluetoothctl 2>/dev/null; " +
                    "sleep 1; " +
                    "echo -e 'connect " + mac + "\\nquit' | bluetoothctl 2>/dev/null"]
                btActionProc.running = true
            }

            function forgetBt(mac) {
                btActionProc.command = ["bash", "-c",
                    "echo -e 'remove " + mac + "\\nquit' | bluetoothctl 2>/dev/null"]
                btActionProc.running = true
            }

            // ══════════════════════════════════════════════════
            //  TIMERS
            // ══════════════════════════════════════════════════

            Timer { id: readyTimer;   interval: 1;   repeat: false; onTriggered: root.ready = true }
            Timer { id: closingTimer; interval: 400; repeat: false; onTriggered: root.isClosing = false }

            // Poll status every 5s
            Timer { interval: 5000; running: true; repeat: true
                onTriggered: {
                    if (!wifiStatusProc.running)  wifiStatusProc.running  = true
                    if (!wifiCurrentProc.running) wifiCurrentProc.running = true
                    if (!btStatusProc.running)    btStatusProc.running    = true
                }
            }
            Timer { interval: 30000; running: true; repeat: true
                onTriggered: { if (!batteryProc.running) batteryProc.running = true }
            }

            // After turning wifi ON, wait 2s then rescan (matches reference)
            Timer {
                id: wifiScanDelayTimer
                interval: 2000
                repeat: false
                onTriggered: root.refreshWifi()
            }

            // After BT toggle ON, wait 1s then refresh (matches reference)
            Timer {
                id: btToggleDelayTimer
                interval: 1000
                repeat: false
                onTriggered: root.refreshBluetooth()
            }

            // After BT action completes, wait 1.5s then refresh (matches reference)
            Timer {
                id: btActionDelayTimer
                interval: 1500
                repeat: false
                onTriggered: root.refreshBluetooth()
            }

            // ══════════════════════════════════════════════════
            //  PROCESSES — WiFi  (exact commands from reference)
            // ══════════════════════════════════════════════════

            // Check if wifi radio is enabled
            Process {
                id: wifiStatusProc
                command: ["bash", "-c", "nmcli radio wifi 2>/dev/null || echo 'disabled'"]
                running: false
                stdout: SplitParser {
                    onRead: (data) => { root.wifiEnabled = data.trim() === "enabled" }
                }
            }

            // Get currently connected network
            Process {
                id: wifiCurrentProc
                command: ["bash", "-c", "nmcli -t -f active,ssid,signal dev wifi 2>/dev/null | grep '^yes' | head -1"]
                running: false
                stdout: SplitParser {
                    onRead: (data) => {
                        var parts = data.trim().split(":")
                        if (parts.length >= 3) {
                            root.wifiConnected = true
                            root.wifiSSID      = parts[1]
                            root.wifiSignal    = parseInt(parts[2]) || 0
                        } else {
                            root.wifiConnected = false
                            root.wifiSSID      = ""
                            root.wifiSignal    = 0
                        }
                    }
                }
            }

            // Scan for networks — same command as reference, simple and reliable
            Process {
                id: wifiScanProc
                command: ["bash", "-c", "nmcli -t -f ssid,signal,security dev wifi list --rescan yes 2>/dev/null | head -20"]
                running: false
                stdout: SplitParser {
                    onRead: (data) => {
                        var line = data.trim()
                        if (line.length === 0) return
                        var parts = line.split(":")
                        if (parts.length < 2) return
                        var ssid = parts[0]
                        if (ssid === "" || ssid === root.wifiSSID) return
                        var signal   = parseInt(parts[1]) || 0
                        var security = parts.length >= 3 ? parts[2] : ""
                        // Deduplicate
                        var current = root.wifiNetworks.slice()
                        for (var i = 0; i < current.length; i++) {
                            if (current[i].ssid === ssid) return
                        }
                        current.push({ ssid: ssid, signal: signal, security: security })
                        root.wifiNetworks = current
                    }
                }
                onRunningChanged: { if (!running) root.wifiScanning = false }
            }

            // Toggle wifi radio — captures enabled state at click time
            Process {
                id: wifiToggleProc
                command: []   // set imperatively
                running: false
                onRunningChanged: {
                    if (!running) {
                        if (!wifiStatusProc.running) wifiStatusProc.running = true
                        if (!root.wifiEnabled) wifiScanDelayTimer.start()
                    }
                }
            }

            // Connect to a wifi network — uses ssid + password properties like reference
            Process {
                id: wifiConnectProc
                property string ssid:     ""
                property string password: ""
                command: {
                    if (password !== "")
                        return ["bash", "-c", "nmcli dev wifi connect '" + ssid + "' password '" + password + "' 2>&1"]
                    else
                        return ["bash", "-c", "nmcli dev wifi connect '" + ssid + "' 2>&1"]
                }
                running: false
                onRunningChanged: {
                    if (!running) {
                        root.wifiConnecting   = false
                        root.wifiPasswordSSID = ""
                        if (!wifiCurrentProc.running) wifiCurrentProc.running = true
                    }
                }
            }

            // Disconnect — same as reference
            Process {
                id: wifiDisconnectProc
                command: ["bash", "-c",
                    "nmcli dev disconnect wlan0 2>/dev/null; " +
                    "nmcli dev disconnect wlp0s20f3 2>/dev/null; " +
                    "nmcli dev disconnect $(nmcli -t -f device,type dev | grep ':wifi$' | cut -d: -f1 | head -1) 2>/dev/null"]
                running: false
                onRunningChanged: {
                    if (!running) {
                        root.wifiConnected = false
                        root.wifiSSID      = ""
                        root.wifiSignal    = 0
                    }
                }
            }

            // ══════════════════════════════════════════════════
            //  PROCESSES — Bluetooth  (exact commands from reference)
            // ══════════════════════════════════════════════════

            // Check BT power state — same as reference btStatusProc
            Process {
                id: btStatusProc
                command: ["bash", "-c",
                    "echo -e 'show\\nquit' | bluetoothctl 2>/dev/null | grep -q 'Powered: yes' && echo 'true' || echo 'false'"]
                running: false
                stdout: SplitParser {
                    onRead: (data) => { root.btEnabled = data.trim() === "true" }
                }
                onRunningChanged: {
                    if (!running && root.btEnabled && !btDevicesProc.running)
                        btDevicesProc.running = true
                }
            }

            // List paired devices — same as reference btDevicesProc
            Process {
                id: btDevicesProc
                command: ["bash", "-c",
                    "echo -e 'devices\\nquit' | bluetoothctl 2>/dev/null | grep '^Device' | " +
                    "while read -r line; do " +
                    "  mac=$(echo \"$line\" | awk '{print $2}'); " +
                    "  name=$(echo \"$line\" | cut -d' ' -f3-); " +
                    "  info=$(echo -e \"info $mac\\nquit\" | bluetoothctl 2>/dev/null); " +
                    "  paired=$(echo \"$info\" | grep -oP 'Paired: \\K\\w+'); " +
                    "  connected=$(echo \"$info\" | grep -oP 'Connected: \\K\\w+'); " +
                    "  if [ \"$paired\" = \"yes\" ]; then echo \"${mac}|${name}|${connected}\"; fi; " +
                    "done"]
                running: false
                stdout: SplitParser {
                    onRead: (data) => {
                        var line = data.trim()
                        if (line.length === 0) return
                        var parts = line.split("|")
                        if (parts.length < 3) return
                        var mac       = parts[0]
                        var name      = parts[1]
                        var connected = parts[2] === "yes"
                        var current   = root.btPairedDevices.slice()
                        for (var i = 0; i < current.length; i++) {
                            if (current[i].mac === mac) return
                        }
                        current.push({ mac: mac, name: name, connected: connected })
                        root.btPairedDevices = current
                        root.btConnected = current.some(function(x) { return x.connected })
                    }
                }
            }

            // BT power ON — separate process like reference
            Process {
                id: btToggleOnProc
                command: ["bash", "-c", "(echo 'power on'; echo 'quit') | bluetoothctl 2>/dev/null"]
                running: false
                onRunningChanged: {
                    if (!running) btToggleDelayTimer.start()
                }
            }

            // BT power OFF — separate process like reference
            Process {
                id: btToggleOffProc
                command: ["bash", "-c", "(echo 'power off'; echo 'quit') | bluetoothctl 2>/dev/null"]
                running: false
                onRunningChanged: {
                    if (!running) {
                        root.btEnabled          = false
                        root.btPairedDevices    = []
                        root.btAvailableDevices = []
                    }
                }
            }

            // BT scan for available devices — same as reference btScanProc
            Process {
                id: btScanProc
                command: ["bash", "-c",
                    "echo -e 'scan on\\nquit' | bluetoothctl 2>/dev/null; " +
                    "sleep 5; " +
                    "echo -e 'scan off\\nquit' | bluetoothctl 2>/dev/null; " +
                    "sleep 1; " +
                    "echo -e 'devices\\nquit' | bluetoothctl 2>/dev/null | grep '^Device' | " +
                    "while read -r line; do " +
                    "  mac=$(echo \"$line\" | awk '{print $2}'); " +
                    "  name=$(echo \"$line\" | cut -d' ' -f3-); " +
                    "  info=$(echo -e \"info $mac\\nquit\" | bluetoothctl 2>/dev/null); " +
                    "  paired=$(echo \"$info\" | grep -oP 'Paired: \\K\\w+'); " +
                    "  if [ \"$paired\" != \"yes\" ] && [ -n \"$name\" ] && [ \"$name\" != \"$mac\" ]; then " +
                    "    echo \"${mac}|${name}\"; " +
                    "  fi; " +
                    "done"]
                running: false
                stdout: SplitParser {
                    onRead: (data) => {
                        var line = data.trim()
                        if (line.length === 0) return
                        var parts = line.split("|")
                        if (parts.length < 2) return
                        var mac  = parts[0]
                        var name = parts[1]
                        if (mac.length !== 17) return
                        var current = root.btAvailableDevices.slice()
                        for (var j = 0; j < current.length; j++) {
                            if (current[j].mac === mac) return
                        }
                        current.push({ mac: mac, name: name })
                        root.btAvailableDevices = current
                    }
                }
                onRunningChanged: { if (!running) root.btScanning = false }
            }

            // Single BT action proc — command set imperatively in helpers above
            Process {
                id: btActionProc
                command: []
                running: false
                onRunningChanged: {
                    if (!running) {
                        root.btConnectingMAC = ""
                        btActionDelayTimer.start()
                    }
                }
            }

            // ══════════════════════════════════════════════════
            //  PROCESSES — Battery
            // ══════════════════════════════════════════════════

            Process {
                id: batteryProc
                command: ["bash", "-c",
                    "cap=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); " +
                    "status=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1); " +
                    "time=''; " +
                    "if command -v upower >/dev/null 2>&1; then " +
                    "  bat=$(upower -e 2>/dev/null | grep -i bat | head -1); " +
                    "  if [ -n \"$bat\" ]; then " +
                    "    if [ \"$status\" = 'Discharging' ]; then " +
                    "      time=$(upower -i \"$bat\" 2>/dev/null | awk '/time to empty/{print $4$5}'); " +
                    "    elif [ \"$status\" = 'Charging' ]; then " +
                    "      time=$(upower -i \"$bat\" 2>/dev/null | awk '/time to full/{print $4$5}'); " +
                    "    fi; fi; fi; " +
                    "[ -z \"$cap\" ] && cap=0; printf '%s|%s|%s\\n' \"$cap\" \"$status\" \"$time\""
                ]
                running: false
                stdout: SplitParser {
                    onRead: (line) => {
                        var p = line.trim().split("|")
                        root.batteryPercent  = parseInt(p[0]) || 0
                        var st = p.length > 1 ? p[1] : ""
                        root.batteryCharging = st === "Charging"
                        root.batteryTime     = p.length > 2 ? p[2] : ""
                        if      (root.batteryCharging)      root.batteryClass = "charging"
                        else if (root.batteryPercent <= 10) root.batteryClass = "critical"
                        else if (root.batteryPercent <= 25) root.batteryClass = "warning"
                        else                                root.batteryClass = ""
                    }
                }
            }

            // ══════════════════════════════════════════════════
            //  LAYER SHELL
            // ══════════════════════════════════════════════════

            screen: modelData
            visible: true
            color: "transparent"
            WlrLayershell.namespace: "quickshell:controlcenter"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.controlCenterOpen
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }

            HyprlandFocusGrab {
                id: grab
                windows: [root]
                property bool canBeActive: root.monitorIsFocused
                active: false
                onCleared: { if (!active) GlobalStates.controlCenterOpen = false }
            }

            Connections {
                target: GlobalStates
                function onControlCenterOpenChanged() {
                    if (GlobalStates.controlCenterOpen) {
                        root.isClosing = false; root.ccHeld = false
                        closingTimer.stop(); root.pollAll(); delayedGrabTimer.start()
                    } else {
                        grab.active = false; root.isClosing = true; closingTimer.restart()
                    }
                }
            }

            Timer {
                id: delayedGrabTimer; interval: 50; repeat: false
                onTriggered: { if (grab.canBeActive) grab.active = GlobalStates.controlCenterOpen }
            }

            // ══════════════════════════════════════════════════
            //  MASKS
            // ══════════════════════════════════════════════════

            Rectangle {
                id: peekStrip
                x: root.width - 7.5; y: 0
                width: 50; height: 175
                visible: false
            }

            Rectangle {
                id: openMask
                x: root.cardX; y: root.panelY
                width: root.panelW
                height: root.panelH
                    + (wifiExpanded.expanded ? wifiExpanded.expandHeight + 8 : 0)
                    + (btExpanded.expanded   ? btExpanded.expandHeight   + 8 : 0)
                visible: false
            }

            Rectangle {
                id: maskExpander
                x: 0; y: 0
                width:  root.ccHeld ? root.width  : 0
                height: root.ccHeld ? root.height : 0
                visible: false
            }

            mask: Region {
                item: (GlobalStates.controlCenterOpen || root.ccHeld) ? openMask : peekStrip
                Region { item: maskExpander }
                Region { item: peekStrip }
            }

            // Dismiss backdrop
            MouseArea {
                anchors.fill: parent
                enabled: root.ccHeld && !GlobalStates.controlCenterOpen
                z: -1
                onClicked: { root.isClosing = true; closingTimer.restart(); root.ccHeld = false }
            }
            MouseArea {
                anchors.fill: parent
                enabled: GlobalStates.controlCenterOpen
                z: -1
                onClicked: GlobalStates.controlCenterOpen = false
            }

            // ══════════════════════════════════════════════════
            //  PEEK HOVER STRIP
            // ══════════════════════════════════════════════════

            MouseArea {
                id: peekHoverArea
                x: root.width - 7.5; y: 0
                width: 50; height: 175
                hoverEnabled: true
                propagateComposedEvents: false
                z: 30
                onEntered: {
                    if (!GlobalStates.controlCenterOpen) {
                        root.ccHeld = true
                        root.pollAll()
                    }
                }
                onExited: {
                    if (!GlobalStates.controlCenterOpen)
                        peekHideTimer.restart()
                }
                onClicked: {
                    if (!GlobalStates.controlCenterOpen) {
                        root.ccHeld = false
                        GlobalStates.controlCenterOpen = true
                    }
                }
            }

            Timer {
                id: peekHideTimer; interval: 800; repeat: false
                onTriggered: {
                    if (!GlobalStates.controlCenterOpen && !panelHover.hovered)
                        root.ccHeld = false
                }
            }

            // Peek visual strip
            Rectangle {
                x: root.width - 7.5; y: 0
                width: 50; height: 175; radius: 15
                color: "#000000"
                opacity: (!root.ccHeld && !GlobalStates.controlCenterOpen && !root.isClosing) ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                z: 25
            }

            // ══════════════════════════════════════════════════
            //  PANEL CARD
            // ══════════════════════════════════════════════════

            Rectangle {
                id: panel
                x: root.cardX
                y: root.panelY
                width: root.panelW
                height: root.panelH
                color: root.bgColor
                radius: root.panelRadius
                border.width: 1; border.color: root.borderColor
                Behavior on color        { ColorAnimation { duration: root.animDuration } }
                Behavior on border.color { ColorAnimation { duration: root.animDuration } }

                // Top gradient accent
                Rectangle {
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    height: 1; z: 3; radius: root.panelRadius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0;  color: "transparent" }
                        GradientStop { position: 0.25; color: root.accentBlue }
                        GradientStop { position: 0.75; color: root.accentPurple }
                        GradientStop { position: 1.0;  color: "transparent" }
                    }
                }

                Rectangle {
                    anchors.fill: parent; radius: parent.radius
                    color: "transparent"; border.width: 1; border.color: root.borderColor; z: 4
                }

                // FIX: propagateComposedEvents: false — was true, which propagated
                // clicks through to whichever tile happened to be underneath.
                MouseArea {
                    anchors.fill: parent
                    enabled: root.ccHeld && !GlobalStates.controlCenterOpen
                    z: 5
                    propagateComposedEvents: false
                    onClicked: { root.ccHeld = false; GlobalStates.controlCenterOpen = true }
                }

                HoverHandler {
                    id: panelHover
                    onHoveredChanged: {
                        if (!hovered && !GlobalStates.controlCenterOpen)
                            peekHideTimer.restart()
                    }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.controlCenterOpen = false; event.accepted = true
                    }
                }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 25; spacing: 25

                    // ── HEADER ──
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8

                        Text {
                            text: "Control Center"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13; font.weight: Font.Bold; color: root.fgColor
                        }

                        Item { Layout.fillWidth: true }

                        // Battery chip
                        RowLayout {
                            spacing: 4
                            visible: root.batteryPercent > 0
                            Text {
                                text: root.batteryCharging ? "󰂄" :
                                      root.batteryPercent > 80 ? "󰁹" :
                                      root.batteryPercent > 60 ? "󰂀" :
                                      root.batteryPercent > 40 ? "󰁾" :
                                      root.batteryPercent > 20 ? "󰁼" : "󰁺"
                                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13
                                color: root.batteryClass === "critical" ? root.accentRed :
                                       root.batteryClass === "warning"  ? "#f9e2af"     :
                                       root.batteryClass === "charging" ? "#a6e3a1"     :
                                       Qt.rgba(1,1,1,0.5)
                            }
                            Text {
                                text: root.batteryPercent + "%"
                                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10
                                color: Qt.rgba(1,1,1,0.4)
                            }
                        }

                        Rectangle {
                            width: 22; height: 22; radius: 11
                            color: closeHov.containsMouse ? Qt.rgba(1,0.3,0.3,0.2) : Qt.rgba(1,1,1,0.05)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent; text: "✕"; font.pixelSize: 9
                                color: closeHov.containsMouse ? Qt.rgba(1,0.3,0.3,0.9) : Qt.rgba(1,1,1,0.7)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            MouseArea {
                                id: closeHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: GlobalStates.controlCenterOpen = false
                            }
                        }
                    }

                    // ── TOGGLE TILES ──
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2; rowSpacing: 25; columnSpacing: 25

                        // ── WiFi tile ──
                        Rectangle {
                            Layout.fillWidth: true; height: 80; radius: root.cornerRadius
                            color: root.wifiEnabled ? Qt.rgba(0.54,0.71,0.98,0.18) : Qt.rgba(1,1,1,0.05)
                            border.width: 1
                            border.color: root.wifiEnabled ? Qt.rgba(0.54,0.71,0.98,0.35) : root.borderColor
                            Behavior on color        { ColorAnimation { duration: root.animDuration } }
                            Behavior on border.color { ColorAnimation { duration: root.animDuration } }

                            ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 5
                                RowLayout { spacing: 6
                                    Text {
                                        text: root.wifiConnected
                                            ? (root.wifiSignal > 66 ? "󰤨" : root.wifiSignal > 33 ? "󰤥" : "󰤟")
                                            : (root.wifiEnabled ? "󰤫" : "󰤭")
                                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 20
                                        color: root.wifiEnabled ? root.accentBlue : Qt.rgba(1,1,1,0.3)
                                        Behavior on color { ColorAnimation { duration: root.animDuration } }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: root.toggleSize; height: root.toggleHeight; radius: root.toggleRadius
                                        color: root.wifiEnabled ? root.accentBlue : Qt.rgba(1,1,1,0.15)
                                        Behavior on color { ColorAnimation { duration: root.animDuration } }
                                        Rectangle {
                                            width: 15; height: 15; radius: 7.5; y: 2
                                            x: root.wifiEnabled ? (root.toggleSize - 17) : 2
                                            color: root.wifiEnabled ? root.bgColor : Qt.rgba(1,1,1,0.6)
                                            Behavior on x { NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }
                                Text {
                                    text: "Wi-Fi"
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Medium
                                    color: root.wifiEnabled ? root.fgColor : Qt.rgba(1,1,1,0.4)
                                    Behavior on color { ColorAnimation { duration: root.animDuration } }
                                }
                                Text {
                                    text: root.wifiConnected ? root.wifiSSID : (root.wifiEnabled ? "Not connected" : "Off")
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9
                                    color: root.wifiConnected ? root.accentBlue : Qt.rgba(1,1,1,0.3)
                                    elide: Text.ElideRight; Layout.fillWidth: true
                                    Behavior on color { ColorAnimation { duration: root.animDuration } }
                                }
                            }

                            // Left = toggle, Right = expand network list
                            MouseArea {
                                id: wifiToggleArea
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (m) => {
                                    m.accepted = true
                                    if (m.button === Qt.RightButton) {
                                        wifiExpanded.expanded = !wifiExpanded.expanded
                                        if (wifiExpanded.expanded && root.wifiNetworks.length === 0)
                                            root.refreshWifi()
                                    } else {
                                        // Capture state before toggling
                                        wifiToggleProc.command = ["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"]
                                        wifiToggleProc.running = true
                                    }
                                }
                            }
                        }

                        // ── Bluetooth tile ──
                        Rectangle {
                            Layout.fillWidth: true; height: 80; radius: root.cornerRadius
                            color: root.btEnabled ? Qt.rgba(0.79,0.65,0.97,0.18) : Qt.rgba(1,1,1,0.05)
                            border.width: 1
                            border.color: root.btEnabled ? Qt.rgba(0.79,0.65,0.97,0.35) : root.borderColor
                            Behavior on color        { ColorAnimation { duration: root.animDuration } }
                            Behavior on border.color { ColorAnimation { duration: root.animDuration } }

                            ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 5
                                RowLayout { spacing: 6
                                    Text {
                                        text: root.btConnected ? "󰂱" : (root.btEnabled ? "󰂯" : "󰂲")
                                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 20
                                        color: root.btEnabled ? root.accentPurple : Qt.rgba(1,1,1,0.3)
                                        Behavior on color { ColorAnimation { duration: root.animDuration } }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        width: root.toggleSize; height: root.toggleHeight; radius: root.toggleRadius
                                        color: root.btEnabled ? root.accentPurple : Qt.rgba(1,1,1,0.15)
                                        Behavior on color { ColorAnimation { duration: root.animDuration } }
                                        Rectangle {
                                            width: 15; height: 15; radius: 7.5; y: 2
                                            x: root.btEnabled ? (root.toggleSize - 17) : 2
                                            color: root.btEnabled ? root.bgColor : Qt.rgba(1,1,1,0.6)
                                            Behavior on x { NumberAnimation { duration: root.animDuration; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }
                                Text {
                                    text: "Bluetooth"
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Medium
                                    color: root.btEnabled ? root.fgColor : Qt.rgba(1,1,1,0.4)
                                    Behavior on color { ColorAnimation { duration: root.animDuration } }
                                }
                                Text {
                                    text: root.btConnected ? "Connected" : (root.btEnabled ? "On" : "Off")
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9
                                    color: root.btConnected ? root.accentPurple : Qt.rgba(1,1,1,0.3)
                                    Behavior on color { ColorAnimation { duration: root.animDuration } }
                                }
                            }

                            // Left = toggle, Right = expand device list
                            MouseArea {
                                id: btToggleArea
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (m) => {
                                    m.accepted = true
                                    if (m.button === Qt.RightButton) {
                                        btExpanded.expanded = !btExpanded.expanded
                                        if (btExpanded.expanded) root.refreshBluetooth()
                                    } else {
                                        // Use separate on/off procs like reference
                                        if (root.btEnabled)
                                            btToggleOffProc.running = true
                                        else
                                            btToggleOnProc.running = true
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ══════════════════════════════════════════════════
            //  WIFI EXPANDED PANEL
            // ══════════════════════════════════════════════════

            Item {
                id: wifiExpanded
                property bool expanded: false
                property real expandHeight: wifiExpandContent.implicitHeight

                x: root.cardX
                y: root.panelY + root.panelH + 6
                width: root.panelW
                height: expanded ? expandHeight : 0
                clip: true

                Behavior on height { NumberAnimation { duration: root.animDuration + 50; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    color: root.bgColorAlt; radius: root.panelRadius
                    border.width: 1; border.color: root.borderColor
                }

                ColumnLayout {
                    id: wifiExpandContent
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 8

                    // Connected network row
                    Rectangle {
                        Layout.fillWidth: true; height: 44; radius: root.cornerRadius
                        color: Qt.rgba(0.54,0.71,0.98,0.12)
                        border.width: 1; border.color: Qt.rgba(0.54,0.71,0.98,0.2)
                        visible: root.wifiConnected
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                            Text {
                                text: root.wifiSignal > 66 ? "󰤨" : root.wifiSignal > 33 ? "󰤥" : "󰤟"
                                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16; color: root.accentBlue
                            }
                            ColumnLayout { Layout.fillWidth: true; spacing: 1
                                Text {
                                    text: root.wifiSSID
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12
                                    color: root.fgColor; font.weight: Font.Medium
                                    elide: Text.ElideRight; Layout.fillWidth: true
                                }
                                Text {
                                    text: "Connected · " + root.wifiSignal + "%"
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9
                                    color: Qt.rgba(1,1,1,0.4)
                                }
                            }
                            Rectangle {
                                width: 26; height: 26; radius: root.cornerRadius
                                color: discHov.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                                Text { anchors.centerIn: parent; text: "󰅖"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; color: Qt.rgba(1,1,1,0.5) }
                                MouseArea {
                                    id: discHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (!wifiDisconnectProc.running) wifiDisconnectProc.running = true }
                                }
                            }
                        }
                    }

                    // Password input
                    Rectangle {
                        Layout.fillWidth: true; height: 36; radius: root.cornerRadius - 2
                        color: Qt.rgba(0.54,0.71,0.98,0.08)
                        border.width: 1; border.color: Qt.rgba(0.54,0.71,0.98,0.3)
                        visible: root.wifiPasswordSSID !== ""
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 8
                            Text { text: "󰌾"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; color: Qt.rgba(1,1,1,0.4) }
                            TextInput {
                                id: wifiPassInput; Layout.fillWidth: true; color: root.fgColor
                                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; echoMode: TextInput.Password
                                Text {
                                    text: "Password for " + root.wifiPasswordSSID
                                    color: Qt.rgba(1,1,1,0.3); visible: !parent.text; font: parent.font
                                }
                                Keys.onReturnPressed: {
                                    if (text.length > 0) {
                                        root.wifiConnecting         = true
                                        wifiConnectProc.ssid        = root.wifiPasswordSSID
                                        wifiConnectProc.password    = text
                                        wifiConnectProc.running     = true
                                        text = ""
                                    }
                                }
                                Keys.onEscapePressed: { root.wifiPasswordSSID = ""; text = "" }
                            }
                            Rectangle {
                                width: 22; height: 22; radius: 6; color: root.accentBlue
                                Text { anchors.centerIn: parent; text: "→"; color: root.bgColor; font.pixelSize: 11; font.weight: Font.Bold }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (wifiPassInput.text.length > 0) {
                                            root.wifiConnecting         = true
                                            wifiConnectProc.ssid        = root.wifiPasswordSSID
                                            wifiConnectProc.password    = wifiPassInput.text
                                            wifiConnectProc.running     = true
                                            wifiPassInput.text = ""
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Networks header
                    RowLayout { Layout.fillWidth: true; visible: root.wifiEnabled
                        Text { text: "Networks"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; color: Qt.rgba(1,1,1,0.4) }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 24; height: 24; radius: 6
                            color: refreshHov.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: root.wifiScanning ? "󰑓" : "󰑐"
                                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; color: Qt.rgba(1,1,1,0.5)
                            }
                            MouseArea {
                                id: refreshHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (!root.wifiScanning) root.refreshWifi() }
                            }
                        }
                    }

                    // Networks list
                    Rectangle {
                        Layout.fillWidth: true; height: 200; radius: root.cornerRadius
                        color: Qt.rgba(1,1,1,0.04); clip: true; visible: root.wifiEnabled
                        border.width: 1; border.color: root.borderColor
                        ListView {
                            anchors.fill: parent; anchors.margins: 4; spacing: 2
                            boundsBehavior: Flickable.StopAtBounds; model: root.wifiNetworks
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 3 }
                            delegate: Rectangle {
                                width: parent ? parent.width : 0; height: 38; radius: root.cornerRadius - 2
                                color: netHov.containsMouse ? Qt.rgba(0.54,0.71,0.98,0.12) : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                                RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                    Text {
                                        text: modelData.signal > 66 ? "󰤨" : modelData.signal > 33 ? "󰤥" : "󰤟"
                                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; color: root.accentBlue
                                    }
                                    ColumnLayout { Layout.fillWidth: true; spacing: 0
                                        Text {
                                            text: modelData.ssid
                                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; color: root.fgColor
                                            elide: Text.ElideRight; Layout.fillWidth: true
                                        }
                                        Text {
                                            text: (modelData.security !== "" && modelData.security !== "--"
                                                   ? "󰌾 " + modelData.security : "Open") + " · " + modelData.signal + "%"
                                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9; color: Qt.rgba(1,1,1,0.35)
                                        }
                                    }
                                }
                                MouseArea {
                                    id: netHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var secured = modelData.security !== "" && modelData.security !== "--"
                                        if (secured) {
                                            root.wifiPasswordSSID = modelData.ssid
                                            wifiPassInput.forceActiveFocus()
                                        } else {
                                            root.wifiConnecting      = true
                                            wifiConnectProc.ssid     = modelData.ssid
                                            wifiConnectProc.password = ""
                                            wifiConnectProc.running  = true
                                        }
                                    }
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: root.wifiScanning ? "Scanning..." : (root.wifiEnabled ? "No networks found" : "Wi-Fi is off")
                                visible: root.wifiNetworks.length === 0
                                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; color: Qt.rgba(1,1,1,0.25)
                            }
                        }
                    }

                    Item { height: 4 }
                }
            }

            // ══════════════════════════════════════════════════
            //  BLUETOOTH EXPANDED PANEL
            // ══════════════════════════════════════════════════

            Item {
                id: btExpanded
                property bool expanded: false
                property real expandHeight: btExpandContent.implicitHeight

                x: root.cardX
                y: root.panelY + root.panelH + (wifiExpanded.expanded ? wifiExpanded.expandHeight + 12 : 6)
                width: root.panelW
                height: expanded ? expandHeight : 0
                clip: true

                Behavior on height { NumberAnimation { duration: root.animDuration + 50; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    color: root.bgColorAlt; radius: root.panelRadius
                    border.width: 1; border.color: root.borderColor
                }

                ColumnLayout {
                    id: btExpandContent
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 8

                    // "Bluetooth is off" placeholder
                    Rectangle {
                        Layout.fillWidth: true; height: 60; radius: root.cornerRadius
                        color: Qt.rgba(1,1,1,0.03); visible: !root.btEnabled
                        border.width: 1; border.color: root.borderColor
                        Text {
                            anchors.centerIn: parent; text: "Bluetooth is off"
                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; color: Qt.rgba(1,1,1,0.25)
                        }
                    }

                    // Paired Devices header
                    RowLayout { Layout.fillWidth: true; visible: root.btEnabled
                        Text { text: "Paired Devices"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; color: Qt.rgba(1,1,1,0.4) }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 52; height: 22; radius: 6
                            color: btScanHov.containsMouse ? Qt.rgba(0.79,0.65,0.97,0.2) : Qt.rgba(1,1,1,0.06)
                            Text { anchors.centerIn: parent; text: root.btScanning ? "Scanning" : "Scan"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9; color: root.accentPurple }
                            MouseArea {
                                id: btScanHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.btScanning) {
                                        root.btScanning = true
                                        root.btAvailableDevices = []
                                        btScanProc.running = true
                                    }
                                }
                            }
                        }
                    }

                    // Paired devices list
                    Rectangle {
                        Layout.fillWidth: true; height: 150; radius: root.cornerRadius
                        color: Qt.rgba(1,1,1,0.04); clip: true; visible: root.btEnabled
                        border.width: 1; border.color: root.borderColor
                        ListView {
                            anchors.fill: parent; anchors.margins: 4; spacing: 2
                            boundsBehavior: Flickable.StopAtBounds; model: root.btPairedDevices
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 3 }
                            delegate: Rectangle {
                                width: parent ? parent.width : 0; height: 42; radius: root.cornerRadius - 2
                                color: btPairedRowHov.containsMouse ? Qt.rgba(1,1,1,0.05) : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                                RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                    Text {
                                        text: modelData.connected ? "󰂱" : "󰂲"
                                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16
                                        color: modelData.connected ? root.accentPurple : Qt.rgba(1,1,1,0.3)
                                    }
                                    ColumnLayout { Layout.fillWidth: true; spacing: 0
                                        Text {
                                            text: modelData.name
                                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
                                            color: modelData.connected ? root.fgColor : Qt.rgba(1,1,1,0.6)
                                            font.weight: modelData.connected ? Font.Medium : Font.Normal
                                            elide: Text.ElideRight; Layout.fillWidth: true
                                        }
                                        Text {
                                            text: root.btConnectingMAC === modelData.mac
                                                  ? "Connecting..." : (modelData.connected ? "Connected" : "Paired")
                                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9
                                            color: Qt.rgba(1,1,1,0.3)
                                        }
                                    }
                                    // Connect / Disconnect button
                                    Rectangle {
                                        width: 26; height: 26; radius: root.cornerRadius
                                        color: btActH.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.connected ? "󰅖" : "󰐕"
                                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
                                            color: modelData.connected ? Qt.rgba(1,0.3,0.4,0.8) : root.accentPurple
                                        }
                                        MouseArea {
                                            id: btActH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.connected) root.disconnectBt(modelData.mac)
                                                else                     root.connectBt(modelData.mac)
                                            }
                                        }
                                    }
                                    // Forget button
                                    Rectangle {
                                        width: 26; height: 26; radius: root.cornerRadius
                                        color: btForgetH.containsMouse ? Qt.rgba(1,0.3,0.3,0.15) : "transparent"
                                        Text {
                                            anchors.centerIn: parent; text: "󰆴"
                                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
                                            color: Qt.rgba(1,1,1,0.3)
                                        }
                                        MouseArea {
                                            id: btForgetH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.forgetBt(modelData.mac)
                                        }
                                    }
                                }
                                // Background hover — z:-1 so buttons still work (like reference)
                                MouseArea {
                                    id: btPairedRowHov; anchors.fill: parent; hoverEnabled: true; z: -1
                                }
                            }
                            Text {
                                anchors.centerIn: parent; text: "No paired devices"
                                visible: root.btPairedDevices.length === 0
                                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; color: Qt.rgba(1,1,1,0.25)
                            }
                        }
                    }

                    // Available Devices header
                    RowLayout { Layout.fillWidth: true; visible: root.btEnabled
                        Text { text: "Available Devices"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; color: Qt.rgba(1,1,1,0.4) }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 60; height: 22; radius: 6
                            color: btAvailScanHov.containsMouse ? Qt.rgba(0.79,0.65,0.97,0.2) : Qt.rgba(1,1,1,0.06)
                            Text { anchors.centerIn: parent; text: root.btScanning ? "Scanning" : "Scan"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9; color: root.accentPurple }
                            MouseArea {
                                id: btAvailScanHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.btScanning) {
                                        root.btScanning = true
                                        root.btAvailableDevices = []
                                        btScanProc.running = true
                                    }
                                }
                            }
                        }
                    }

                    // Available devices list
                    Rectangle {
                        Layout.fillWidth: true; height: 130; radius: root.cornerRadius
                        color: Qt.rgba(1,1,1,0.04); clip: true; visible: root.btEnabled
                        border.width: 1; border.color: root.borderColor
                        ListView {
                            anchors.fill: parent; anchors.margins: 4; spacing: 2
                            boundsBehavior: Flickable.StopAtBounds; model: root.btAvailableDevices
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 3 }
                            delegate: Rectangle {
                                width: parent ? parent.width : 0; height: 38; radius: root.cornerRadius - 2
                                color: btAvailHov.containsMouse ? Qt.rgba(0.79,0.65,0.97,0.12) : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                                RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                    Text { text: "󰂲"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16; color: Qt.rgba(1,1,1,0.4) }
                                    Text {
                                        text: modelData.name
                                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; color: root.fgColor
                                        elide: Text.ElideRight; Layout.fillWidth: true
                                    }
                                    Text {
                                        text: "..."
                                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; color: root.accentPurple
                                        visible: root.btConnectingMAC === modelData.mac
                                    }
                                }
                                MouseArea {
                                    id: btAvailHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pairBt(modelData.mac)
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: root.btScanning ? "Scanning for devices..." : "Press Scan to find devices"
                                visible: root.btAvailableDevices.length === 0
                                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; color: Qt.rgba(1,1,1,0.25)
                            }
                        }
                    }

                    Item { height: 4 }
                }
            }
        }
    }
}
