import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Widgets
import Quickshell.Io
import Qt5Compat.GraphicalEffects

PanelWindow {
    id: wpRoot

    property bool wpVisible: false
    property real systemBrightness: 0
    property int maxBrightness: 120000
    property bool isDragging: false
    property bool nightLightActive: false
    property int currentTab: 1

    property int displayMonth: new Date().getMonth()
    property int displayYear: new Date().getFullYear()

    signal requestClose()

    property var sink: Pipewire.defaultAudioSink
    property bool shouldShowOsd: false

    property var activePlayer: Mpris.players.count > 0 ? Mpris.players.get(0) : null

    property bool isBooting: true
    Timer {
        id: bootTimer
        interval: 2000
        running: true
        onTriggered: isBooting = false
    }

    Timer {
        interval: 2000
        running: wpRoot.wpVisible && currentTab === 1
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            cpuStatsProcess.running = true;
            ramStatsProcess.running = true;
            diskStatsProcess.running = true;
        }
    }

    Process {
        id: cpuStatsProcess
        command: ["sh", "-c", "top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\\([0-9.]*\\)%* id.*/\\1/' | awk '{print 100 - $1}'"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                if (cpuCanvas) { cpuCanvas.percentage = parseFloat(data.trim()) || 0; cpuCanvas.requestPaint(); }
            }
        }
    }

    Process {
        id: ramStatsProcess
        command: ["sh", "-c", "free | grep Mem | awk '{printf \"%.2f|%.2f|%.2f\\n\", ($3/$2)*100.0, $3/1048576.0, $2/1048576.0}'"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                if (ramCanvas) {
                    var parts = data.trim().split("|");
                    ramCanvas.percentage = parseFloat(parts[0]) || 0;
                    ramCanvas.usedGb = parseFloat(parts[1]) || 0;
                    ramCanvas.totalGb = parseFloat(parts[2]) || 0;
                    ramCanvas.requestPaint();
                }
            }
        }
    }

    Process {
        id: diskStatsProcess
        command: ["sh", "-c", "df / | awk 'NR==2 {printf \"%.2f|%.2f|%.2f\\n\", ($3/$2)*100.0, $3/1048576.0, $2/1048576.0}'"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                if (diskCanvas) {
                    var parts = data.trim().split("|");
                    diskCanvas.percentage = parseFloat(parts[0]) || 0;
                    diskCanvas.usedGb = parseFloat(parts[1]) || 0;
                    diskCanvas.totalGb = parseFloat(parts[2]) || 0;
                    diskCanvas.requestPaint();
                }
            }
        }
    }

    onWpVisibleChanged: {
        if (wpVisible) {
            currentTab = 1;
            let now = new Date();
            displayMonth = now.getMonth();
            displayYear = now.getFullYear();
            if (!isBooting && !brightnessSyncDebounce.running) brightnessSyncDebounce.start();
            mainPanel.forceActiveFocus();
            wpRoot.forceActiveFocus();
        }
    }

    function navigateMonth(step) {
        let newDate = new Date(displayYear, displayMonth + step, 1);
        displayMonth = newDate.getMonth();
        displayYear = newDate.getFullYear();
    }

    Process {
        id: nightLightProcess
        command: ["hyprsunset", "-t", "4000"]
        running: false
    }

    function toggleNightLight() {
        nightLightActive = !nightLightActive;
        if (nightLightActive) {
            nightLightProcess.running = true;
        } else {
            nightLightProcess.running = false;
            killNightLight.running = true;
        }
    }

    Process {
        id: killNightLight
        command: ["pkill", "hyprsunset"]
        running: false
    }

    Process {
        id: initMaxBrightness
        command: ["brightnessctl", "m"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let val = parseInt(this.text.trim());
                if (val > 0) wpRoot.maxBrightness = val;
            }
        }
    }

    Timer {
        id: brightnessSyncDebounce
        interval: 1
        repeat: false
        onTriggered: {
            if (!setBrightnessProcess.running) {
                setBrightnessProcess.command = ["brightnessctl", "set", Math.round(wpRoot.systemBrightness).toString()];
                setBrightnessProcess.running = true;
            } else {
                brightnessSyncDebounce.interval = 10;
                brightnessSyncDebounce.start();
            }
        }
    }

    onSystemBrightnessChanged: {
        if (!isBooting && (wpVisible || shouldShowOsd || isDragging)) {
            if (!brightnessSyncDebounce.running) brightnessSyncDebounce.start();
        }
    }

    Process { id: setBrightnessProcess; running: false }

    Timer {
        id: pollTimer
        interval: 1
        running: !wpRoot.isDragging && !brightnessSyncDebounce.running
        repeat: true
        onTriggered: { if (!getBrightnessProcess.running) getBrightnessProcess.running = true; }
    }

    Process {
        id: getBrightnessProcess
        command: ["brightnessctl", "g"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let current = parseInt(this.text.trim());
                if (!isNaN(current) && Math.abs(current - wpRoot.systemBrightness) > 2) {
                    if (!wpRoot.isDragging && !brightnessSyncDebounce.running) {
                        wpRoot.systemBrightness = current;
                        if (!wpRoot.wpVisible && !wpRoot.isBooting) triggerOsd();
                    }
                }
            }
        }
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
        onObjectsChanged: { wpRoot.sink = Pipewire.defaultAudioSink; }
    }

    function triggerOsd() {
        if (!wpRoot.wpVisible && !wpRoot.isBooting) {
            wpRoot.shouldShowOsd = true;
            osdHideTimer.restart();
        }
    }

    Timer {
        id: osdHideTimer
        interval: 750
        onTriggered: {
            if (!osdMainMouseArea.containsMouse && !wpRoot.isDragging) {
                wpRoot.shouldShowOsd = false;
            } else {
                osdHideTimer.restart();
            }
        }
    }

    Connections {
        target: Pipewire.defaultAudioSink?.audio
        ignoreUnknownSignals: true
        function onVolumeChanged() { triggerOsd(); }
        function onMutedChanged() { triggerOsd(); }
    }

    Process { id: openWifi; command: ["nm-connection-editor"]; running: false }
    Process { id: openBluetooth; command: ["blueman-manager"]; running: false }

    function formatTime(microseconds) {
        if (!microseconds || microseconds === 0 || microseconds < 0) return "0:00"
        const seconds = Math.floor(microseconds / 1000000)
        const mins = Math.floor(seconds / 60)
        const secs = seconds % 60
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }

    // --- MAIN WINDOW ---
    visible: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: wpVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: 0
    anchors.top: true
    margins.top: (wpVisible || mainLayoutMouseArea.containsMouse) ? 0 : -493.5
    Behavior on margins.top { NumberAnimation { duration: 150 } }
    implicitWidth: 600
    implicitHeight: 500

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape && wpRoot.wpVisible) {
            wpRoot.wpVisible = false;
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: wpRoot.wpVisible
        z: -1
        onClicked: {
            wpRoot.wpVisible = false;
        }
    }

    MouseArea {
        id: peekHoverArea
        anchors.top: parent.top
        anchors.right: parent.right
        width: 600
        height: 10
        hoverEnabled: true
        propagateComposedEvents: true
        z: 2
        onEntered: {
            if (!wpRoot.wpVisible) wpRoot.wpVisible = true
        }
        onPressed: (mouse) => mouse.accepted = false
    }

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        spacing: 5

        Rectangle {
            id: mainPanel
            Layout.preferredWidth: 600
            Layout.preferredHeight: 500
            Layout.alignment: Qt.AlignRight
            color: "#000000"
            radius: 0
            focus: true
            
            // Ensure focus for keyboard events
            Component.onCompleted: { mainPanel.forceActiveFocus(); }
            
            // Clip bottom corners with radius
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: mainPanel.width
                    height: mainPanel.height
                    radius: 15
                    Rectangle {
                        width: mainPanel.width
                        height: mainPanel.height / 2
                        y: 0
                        color: "white"
                    }
                }
            }

            Behavior on opacity { NumberAnimation { duration: 200 } }

            MouseArea {
                id: mainLayoutMouseArea
                anchors.fill: parent
                parent: mainLayout
                hoverEnabled: true
                onEntered: { wpRoot.wpVisible = true; }
                propagateComposedEvents: true
                onPressed: (mouse) => mouse.accepted = false
            }

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape) {
                    wpRoot.wpVisible = false;
                    wpRoot.requestClose();
                    event.accepted = true;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.preferredHeight: 24; Layout.fillWidth: true; color: "transparent"
                        Text { text: "Media"; font.pixelSize: 13; font.weight: Font.Bold; color: currentTab === 0 ? "white" : "#71717a"; anchors.centerIn: parent }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; visible: currentTab === 0; gradient: Gradient { GradientStop { position: 0.0; color: "#89b4fa" } GradientStop { position: 1.0; color: "#cba6f7" } } }
                        MouseArea { anchors.fill: parent; onClicked: currentTab = 0; cursorShape: Qt.PointingHandCursor }
                    }

                    Rectangle {
                        Layout.preferredHeight: 24; Layout.fillWidth: true; color: "transparent"
                        Text { text: "System"; font.pixelSize: 13; font.weight: Font.Bold; color: currentTab === 1 ? "white" : "#71717a"; anchors.centerIn: parent }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; visible: currentTab === 1; gradient: Gradient { GradientStop { position: 0.0; color: "#89b4fa" } GradientStop { position: 1.0; color: "#cba6f7" } } }
                        MouseArea { anchors.fill: parent; onClicked: currentTab = 1; cursorShape: Qt.PointingHandCursor }
                    }

                    Rectangle {
                        Layout.preferredHeight: 24; Layout.fillWidth: true; color: "transparent"
                        Text { text: "Calendar"; font.pixelSize: 13; font.weight: Font.Bold; color: currentTab === 2 ? "white" : "#71717a"; anchors.centerIn: parent }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; visible: currentTab === 2; gradient: Gradient { GradientStop { position: 0.0; color: "#89b4fa" } GradientStop { position: 1.0; color: "#cba6f7" } } }
                        MouseArea { anchors.fill: parent; onClicked: currentTab = 2; cursorShape: Qt.PointingHandCursor }
                    }
                }

                StackLayout {
                    currentIndex: currentTab
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // ── MEDIA ──
                    Item {
                        MediaSection { anchors.fill: parent; anchors.margins: 5 }
                    }

                    // ── SYSTEM TAB ──
                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 10

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "System Resources"
                                font.family: "JetBrains Mono Nerd Font"
                                font.pixelSize: 11
                                color: "#3f3f46"
                                Layout.topMargin: 2
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 10

                                // ── CPU CARD ──
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: "#0d0d0f"
                                    radius: 20
                                    border.width: 1
                                    border.color: "#1e1e23"

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Item {
                                            Layout.alignment: Qt.AlignHCenter
                                            implicitWidth: 24; implicitHeight: 24
                                            Text { id: cpuIcon; text: ""; font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 18; visible: false; anchors.centerIn: parent }
                                            LinearGradient { anchors.fill: cpuIcon; source: cpuIcon; gradient: Gradient { GradientStop { position: 0.0; color: "#89b4fa" } GradientStop { position: 1.0; color: "#74c7ec" } } }
                                        }

                                        Canvas {
                                            id: cpuCanvas; width: 130; height: 130
                                            property real percentage: 0
                                            Layout.alignment: Qt.AlignHCenter
                                            onPaint: {
                                                var ctx = getContext("2d"); ctx.reset();
                                                var cx = width/2, cy = height/2, r = 52;
                                                ctx.beginPath(); ctx.arc(cx, cy, r+10, 0, 2*Math.PI);
                                                ctx.strokeStyle = "rgba(137,180,250,0.04)"; ctx.lineWidth = 2; ctx.stroke();
                                                ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2*Math.PI);
                                                ctx.strokeStyle = "#1a1a1f"; ctx.lineWidth = 13; ctx.stroke();
                                                var startAngle = -Math.PI/2;
                                                var endAngle = startAngle + (percentage/100)*2*Math.PI;
                                                var isHot = percentage > 80;
                                                var baseColor = isHot ? "#f38ba8" : "#89b4fa";
                                                var glowColor = isHot ? "rgba(243,139,168,0.25)" : "rgba(137,180,250,0.25)";
                                                if (percentage > 0) {
                                                    ctx.beginPath(); ctx.arc(cx, cy, r, startAngle, endAngle);
                                                    ctx.strokeStyle = glowColor; ctx.lineWidth = 22; ctx.lineCap = "round"; ctx.stroke();
                                                    ctx.beginPath(); ctx.arc(cx, cy, r, startAngle, endAngle);
                                                    ctx.strokeStyle = baseColor; ctx.lineWidth = 13; ctx.lineCap = "round"; ctx.stroke();
                                                    ctx.beginPath();
                                                    ctx.arc(cx + r*Math.cos(endAngle), cy + r*Math.sin(endAngle), 5, 0, 2*Math.PI);
                                                    ctx.fillStyle = "white"; ctx.fill();
                                                }
                                            }
                                            ColumnLayout {
                                                anchors.centerIn: parent; spacing: -1
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: Math.round(cpuCanvas.percentage) + "%"
                                                    font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 20; font.weight: Font.Bold; color: "white"
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: "usage"
                                                    font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 9; color: "#52525b"
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "CPU"
                                            font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold; color: "#52525b"
                                        }
                                    }
                                }

                                // ── RAM CARD ──
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: "#0d0d0f"
                                    radius: 20
                                    border.width: 1
                                    border.color: "#1e1e23"

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Item {
                                            Layout.alignment: Qt.AlignHCenter
                                            implicitWidth: 24; implicitHeight: 24
                                            Text { id: ramIcon; text: "󰍛"; font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 18; visible: false; anchors.centerIn: parent }
                                            LinearGradient { anchors.fill: ramIcon; source: ramIcon; gradient: Gradient { GradientStop { position: 0.0; color: "#cba6f7" } GradientStop { position: 1.0; color: "#f5c2e7" } } }
                                        }

                                        Canvas {
                                            id: ramCanvas; width: 130; height: 130
                                            property real percentage: 0
                                            property real usedGb: 0
                                            property real totalGb: 0
                                            Layout.alignment: Qt.AlignHCenter
                                            onPaint: {
                                                var ctx = getContext("2d"); ctx.reset();
                                                var cx = width/2, cy = height/2, r = 52;
                                                ctx.beginPath(); ctx.arc(cx, cy, r+10, 0, 2*Math.PI);
                                                ctx.strokeStyle = "rgba(203,166,247,0.04)"; ctx.lineWidth = 2; ctx.stroke();
                                                ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2*Math.PI);
                                                ctx.strokeStyle = "#1a1a1f"; ctx.lineWidth = 13; ctx.stroke();
                                                var startAngle = -Math.PI/2;
                                                var endAngle = startAngle + (percentage/100)*2*Math.PI;
                                                var isHot = percentage > 80;
                                                var baseColor = isHot ? "#f38ba8" : "#cba6f7";
                                                var glowColor = isHot ? "rgba(243,139,168,0.25)" : "rgba(203,166,247,0.25)";
                                                if (percentage > 0) {
                                                    ctx.beginPath(); ctx.arc(cx, cy, r, startAngle, endAngle);
                                                    ctx.strokeStyle = glowColor; ctx.lineWidth = 22; ctx.lineCap = "round"; ctx.stroke();
                                                    ctx.beginPath(); ctx.arc(cx, cy, r, startAngle, endAngle);
                                                    ctx.strokeStyle = baseColor; ctx.lineWidth = 13; ctx.lineCap = "round"; ctx.stroke();
                                                    ctx.beginPath();
                                                    ctx.arc(cx + r*Math.cos(endAngle), cy + r*Math.sin(endAngle), 5, 0, 2*Math.PI);
                                                    ctx.fillStyle = "white"; ctx.fill();
                                                }
                                            }
                                            ColumnLayout {
                                                anchors.centerIn: parent; spacing: -1
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: Math.round(ramCanvas.percentage) + "%"
                                                    font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 20; font.weight: Font.Bold; color: "white"
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: ramCanvas.usedGb.toFixed(1) + " / " + ramCanvas.totalGb.toFixed(1) + " GB"
                                                    font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 9; color: "#71717a"
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "RAM"
                                            font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold; color: "#52525b"
                                        }
                                    }
                                }

                                // ── DISK CARD ──
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: "#0d0d0f"
                                    radius: 20
                                    border.width: 1
                                    border.color: "#1e1e23"

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Item {
                                            Layout.alignment: Qt.AlignHCenter
                                            implicitWidth: 24; implicitHeight: 24
                                            Text { id: diskIcon; text: "󰋊"; font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 18; visible: false; anchors.centerIn: parent }
                                            LinearGradient { anchors.fill: diskIcon; source: diskIcon; gradient: Gradient { GradientStop { position: 0.0; color: "#a6e3a1" } GradientStop { position: 1.0; color: "#94e2d5" } } }
                                        }

                                        Canvas {
                                            id: diskCanvas; width: 130; height: 130
                                            property real percentage: 0
                                            property real usedGb: 0
                                            property real totalGb: 0
                                            Layout.alignment: Qt.AlignHCenter
                                            onPaint: {
                                                var ctx = getContext("2d"); ctx.reset();
                                                var cx = width/2, cy = height/2, r = 52;
                                                ctx.beginPath(); ctx.arc(cx, cy, r+10, 0, 2*Math.PI);
                                                ctx.strokeStyle = "rgba(166,227,161,0.04)"; ctx.lineWidth = 2; ctx.stroke();
                                                ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2*Math.PI);
                                                ctx.strokeStyle = "#1a1a1f"; ctx.lineWidth = 13; ctx.stroke();
                                                var startAngle = -Math.PI/2;
                                                var endAngle = startAngle + (percentage/100)*2*Math.PI;
                                                var isHot = percentage > 80;
                                                var baseColor = isHot ? "#f38ba8" : "#a6e3a1";
                                                var glowColor = isHot ? "rgba(243,139,168,0.25)" : "rgba(166,227,161,0.25)";
                                                if (percentage > 0) {
                                                    ctx.beginPath(); ctx.arc(cx, cy, r, startAngle, endAngle);
                                                    ctx.strokeStyle = glowColor; ctx.lineWidth = 22; ctx.lineCap = "round"; ctx.stroke();
                                                    ctx.beginPath(); ctx.arc(cx, cy, r, startAngle, endAngle);
                                                    ctx.strokeStyle = baseColor; ctx.lineWidth = 13; ctx.lineCap = "round"; ctx.stroke();
                                                    ctx.beginPath();
                                                    ctx.arc(cx + r*Math.cos(endAngle), cy + r*Math.sin(endAngle), 5, 0, 2*Math.PI);
                                                    ctx.fillStyle = "white"; ctx.fill();
                                                }
                                            }
                                            ColumnLayout {
                                                anchors.centerIn: parent; spacing: -1
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: Math.round(diskCanvas.percentage) + "%"
                                                    font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 20; font.weight: Font.Bold; color: "white"
                                                }
                                                Text {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: diskCanvas.usedGb.toFixed(1) + " / " + diskCanvas.totalGb.toFixed(1) + " GB"
                                                    font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 9; color: "#71717a"
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "Disk"
                                            font.family: "JetBrains Mono Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold; color: "#52525b"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── CALENDAR ──
                    Item {
                        id: calendarTab
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 80
                                color: "#0a0a0a"
                                radius: 20
                                border.width: 1
                                border.color: "#1a1a1a"
                                clip: true

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 18
                                    anchors.rightMargin: 18
                                    anchors.topMargin: 12
                                    anchors.bottomMargin: 12
                                    spacing: 0

                                    Rectangle {
                                        width: 32; height: 32; radius: 16
                                        color: calPrevHover.containsMouse ? "#1a1a1a" : "transparent"
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Item {
                                            anchors.centerIn: parent
                                            implicitWidth: 18; implicitHeight: 18
                                            Text { id: calPrevIcon; text: "󰁍"; font.family: "CaskaydiaCove Nerd Font"; font.pixelSize: 18; visible: false; anchors.centerIn: parent }
                                            LinearGradient { anchors.fill: calPrevIcon; source: calPrevIcon; gradient: Gradient { GradientStop { position: 0.0; color: "#89b4fa" } GradientStop { position: 1.0; color: "#cba6f7" } } }
                                        }
                                        HoverHandler { id: calPrevHover }
                                        MouseArea { anchors.fill: parent; onClicked: navigateMonth(-1); cursorShape: Qt.PointingHandCursor }
                                    }

                                    Item { Layout.fillWidth: true }

                                    ColumnLayout {
                                        spacing: 2
                                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

                                        Item {
                                            Layout.alignment: Qt.AlignHCenter
                                            implicitWidth: calMonthLabel.contentWidth
                                            implicitHeight: calMonthLabel.contentHeight
                                            Text {
                                                id: calMonthLabel
                                                text: Qt.formatDateTime(new Date(displayYear, displayMonth, 1), "MMMM")
                                                font.family: "JetBrains Mono Nerd Font"
                                                font.pixelSize: 22
                                                font.weight: Font.Black
                                                visible: false
                                            }
                                            LinearGradient {
                                                anchors.fill: calMonthLabel
                                                source: calMonthLabel
                                                gradient: Gradient {
                                                    GradientStop { position: 0.0; color: "#ffffff" }
                                                    GradientStop { position: 1.0; color: "#aaaaaa" }
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: displayYear
                                            font.family: "JetBrains Mono Nerd Font"
                                            font.pixelSize: 11
                                            color: "#52525b"
                                            font.weight: Font.Medium
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Rectangle {
                                        width: 32; height: 32; radius: 16
                                        color: calNextHover.containsMouse ? "#1a1a1a" : "transparent"
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Item {
                                            anchors.centerIn: parent
                                            implicitWidth: 18; implicitHeight: 18
                                            Text { id: calNextIcon; text: "󰁔"; font.family: "CaskaydiaCove Nerd Font"; font.pixelSize: 18; visible: false; anchors.centerIn: parent }
                                            LinearGradient { anchors.fill: calNextIcon; source: calNextIcon; gradient: Gradient { GradientStop { position: 0.0; color: "#89b4fa" } GradientStop { position: 1.0; color: "#cba6f7" } } }
                                        }
                                        HoverHandler { id: calNextHover }
                                        MouseArea { anchors.fill: parent; onClicked: navigateMonth(1); cursorShape: Qt.PointingHandCursor }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: "#070707"
                                radius: 20
                                border.width: 1
                                border.color: "#111111"

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Repeater {
                                            model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                                            delegate: Item {
                                                Layout.fillWidth: true
                                                height: 24
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData
                                                    font.family: "JetBrains Mono Nerd Font"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    color: (index === 0 || index === 6) ? "#3a3a4a" : "#3f3f46"
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: "#1a1a24"
                                    }

                                    MonthGrid {
                                        id: calGrid
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        month: wpRoot.displayMonth
                                        year: wpRoot.displayYear
                                        spacing: 0

                                        delegate: Rectangle {
                                            implicitWidth: calGrid.width / 7
                                            implicitHeight: (calGrid.height) / 6
                                            color: "transparent"
                                            radius: 10

                                            readonly property bool isToday: {
                                                let now = new Date();
                                                return model.day === now.getDate() && model.month === now.getMonth() && model.year === now.getFullYear();
                                            }
                                            readonly property bool isCurrentMonth: model.month === displayMonth
                                            readonly property bool isWeekend: model.dayOfWeek === 0 || model.dayOfWeek === 6

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 32; height: 32; radius: 16
                                                visible: isToday
                                                gradient: Gradient {
                                                    GradientStop { position: 0.0; color: "#89b4fa" }
                                                    GradientStop { position: 1.0; color: "#cba6f7" }
                                                }
                                            }

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 32; height: 32; radius: 10
                                                color: "white"
                                                opacity: dayHover.containsMouse && !isToday ? 0.06 : 0
                                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: model.day
                                                font.family: "JetBrains Mono Nerd Font"
                                                font.pixelSize: 12
                                                font.weight: isToday ? Font.Bold : Font.Normal
                                                color: isToday ? "#11111b" : (isCurrentMonth ? (isWeekend ? "#52525b" : "#a1a1aa") : "#27272a")
                                            }

                                            HoverHandler { id: dayHover }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    width: 90; height: 30; radius: 15
                                    color: todayBtnHover.containsMouse ? "#1e1e2e" : "#0d0d14"
                                    border.width: 1
                                    border.color: todayBtnHover.containsMouse ? "#89b4fa" : "#2a2a3a"
                                    Behavior on border.color { ColorAnimation { duration: 200 } }
                                    Behavior on color { ColorAnimation { duration: 200 } }

                                    Item {
                                        anchors.centerIn: parent
                                        implicitWidth: calTodayBtn.contentWidth
                                        implicitHeight: calTodayBtn.contentHeight
                                        Text {
                                            id: calTodayBtn
                                            text: "Today"
                                            font.family: "JetBrains Mono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            visible: false
                                        }
                                        LinearGradient {
                                            anchors.fill: calTodayBtn
                                            source: calTodayBtn
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: todayBtnHover.containsMouse ? "#89b4fa" : "#52525b" }
                                                GradientStop { position: 1.0; color: todayBtnHover.containsMouse ? "#cba6f7" : "#52525b" }
                                            }
                                        }
                                    }

                                    HoverHandler { id: todayBtnHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            let now = new Date();
                                            displayMonth = now.getMonth();
                                            displayYear = now.getFullYear();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- OSD WINDOW ---
    PanelWindow {
        id: osdWindow
        visible: true
        color: "transparent"
        mask: Region { item: osdContainer }

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "osd-overlay"
        WlrLayershell.exclusiveZone: 0
        anchors.right: true
        margins.right: (wpRoot.shouldShowOsd || osdMainMouseArea.containsMouse) ? -1.5 : -178.5
        Behavior on margins.right { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        implicitWidth: 185
        implicitHeight: 270

        Rectangle {
            id: osdContainer
            anchors.fill: parent
            color: "#000000"

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: osdContainer.width; height: osdContainer.height; radius: 15
                    Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 20; color: "black" }
                }
            }

            RowLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 15

                ColumnLayout {
                    Layout.fillHeight: true; Layout.preferredWidth: 60; spacing: 12
                    Item {
                        Layout.fillWidth: true; Layout.preferredHeight: 20
                        Text { id: osdBrightText; text: Math.round((wpRoot.systemBrightness / Math.max(1, wpRoot.maxBrightness)) * 100) + "%"; font.pixelSize: 12; font.weight: Font.Bold; anchors.centerIn: parent; visible: false }
                        LinearGradient { anchors.fill: osdBrightText; source: ShaderEffectSource { sourceItem: osdBrightText; hideSource: true } gradient: Gradient { GradientStop { position: 0.0; color: "#89b4fa" } GradientStop { position: 1.0; color: "#cba6f7" } } }
                    }
                    Rectangle {
                        Layout.fillHeight: true; Layout.preferredWidth: 60; Layout.alignment: Qt.AlignHCenter; radius: 15
                        color: Qt.rgba(1, 1, 1, 0.08)
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; radius: 15; height: parent.height * Math.min(1.0, (wpRoot.systemBrightness / Math.max(1, wpRoot.maxBrightness))); gradient: Gradient { GradientStop { position: 0.0; color: "#89b4fa" } GradientStop { position: 1.0; color: "#cba6f7" } } }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            onPressed: (mouse) => { wpRoot.isDragging = true; let val = (1 - (mouse.y / height)) * wpRoot.maxBrightness; wpRoot.systemBrightness = Math.max(0, Math.min(wpRoot.maxBrightness, val)); }
                            onPositionChanged: (mouse) => { if (pressed) { let val = (1 - (mouse.y / height)) * wpRoot.maxBrightness; wpRoot.systemBrightness = Math.max(0, Math.min(wpRoot.maxBrightness, val)); } }
                            onReleased: wpRoot.isDragging = false
                            onWheel: (wheel) => { let step = wpRoot.maxBrightness * 0.01; wpRoot.systemBrightness = Math.max(0, Math.min(wpRoot.maxBrightness, wpRoot.systemBrightness + (wheel.angleDelta.y > 0 ? step : -step))); }
                        }
                    }
                    Item {
                        Layout.fillWidth: true; Layout.preferredHeight: 35
                        Text { id: osdBIcon; anchors.centerIn: parent; font.pixelSize: 22; visible: false; text: wpRoot.nightLightActive ? "󰽥" : "󰖨" }
                        LinearGradient { anchors.fill: osdBIcon; source: ShaderEffectSource { sourceItem: osdBIcon; hideSource: true } gradient: Gradient { GradientStop { position: 0.0; color: "#89b4fa" } GradientStop { position: 1.0; color: "#cba6f7" } } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: wpRoot.toggleNightLight() }
                    }
                }

                ColumnLayout {
                    Layout.fillHeight: true; Layout.preferredWidth: 60; spacing: 12
                    Item {
                        Layout.fillWidth: true; Layout.preferredHeight: 20
                        Text { id: osdVolText; text: Math.round((sink?.audio?.volume || 0) * 100) + "%"; font.pixelSize: 12; font.weight: Font.Bold; anchors.centerIn: parent; visible: false }
                        LinearGradient { anchors.fill: osdVolText; source: ShaderEffectSource { sourceItem: osdVolText; hideSource: true } gradient: Gradient { GradientStop { position: 0.0; color: "#89b4fa" } GradientStop { position: 1.0; color: "#cba6f7" } } }
                    }
                    Rectangle {
                        Layout.fillHeight: true; Layout.preferredWidth: 60; Layout.alignment: Qt.AlignHCenter; radius: 15
                        color: Qt.rgba(1, 1, 1, 0.08)
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; radius: 15; height: parent.height * Math.min(1.0, (sink?.audio?.volume ?? 0)); gradient: Gradient { GradientStop { position: 0.0; color: "#89b4fa" } GradientStop { position: 1.0; color: "#cba6f7" } } }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            onPressed: (mouse) => { if (sink?.audio) { wpRoot.isDragging = true; sink.audio.volume = Math.max(0, Math.min(1.0, 1 - (mouse.y / height))); } }
                            onPositionChanged: (mouse) => { if (pressed && sink?.audio) { sink.audio.volume = Math.max(0, Math.min(1.0, 1 - (mouse.y / height))); } }
                            onReleased: wpRoot.isDragging = false
                            onWheel: (wheel) => { if (sink?.audio) { let step = 0.01; sink.audio.volume = Math.max(0, Math.min(1.0, sink.audio.volume + (wheel.angleDelta.y > 0 ? step : -step))); } }
                        }
                    }
                    Item {
                        Layout.fillWidth: true; Layout.preferredHeight: 35
                        Text { id: osdVIcon; anchors.centerIn: parent; font.pixelSize: 22; visible: false; text: sink?.audio?.muted ? "󰖁" : "󰕾" }
                        LinearGradient { anchors.fill: osdVIcon; source: ShaderEffectSource { sourceItem: osdVIcon; hideSource: true } gradient: Gradient { GradientStop { position: 0.0; color: "#89b4fa" } GradientStop { position: 1.0; color: "#cba6f7" } } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (sink?.audio) sink.audio.muted = !sink.audio.muted }
                    }
                }
            }

            MouseArea {
                id: osdMainMouseArea
                anchors.fill: parent; hoverEnabled: true; propagateComposedEvents: true
                onEntered: { osdHideTimer.stop(); wpRoot.shouldShowOsd = true; }
                onExited: { if (!wpRoot.isDragging) osdHideTimer.restart(); }
                onPressed: (mouse) => mouse.accepted = false
            }
        }
    }
}