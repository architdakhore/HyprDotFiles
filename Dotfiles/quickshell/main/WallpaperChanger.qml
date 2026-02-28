import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: wallpaperScope

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: root
            required property var modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

            property bool isClosing: false
            property bool ready: false
            property string activeWallpaper: ""
            property string searchQuery: ""

            readonly property int panelW: 860
            readonly property int panelH: 640

            property real cardX: GlobalStates.wallpaperOpen
                ? 15
                : -root.panelW - 20

            Behavior on cardX {
                enabled: root.ready
                NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
            }

            Component.onCompleted: {
                readyTimer.start()
                wallpaperScanner.running = true
            }

            Timer {
                id: readyTimer
                interval: 1
                repeat: false
                onTriggered: root.ready = true
            }

            Timer {
                id: closingTimer
                interval: 400
                repeat: false
                onTriggered: root.isClosing = false
            }

            property var wallpapers: []

            Process {
                id: wallpaperScanner
                command: ["bash", "-c", "find /home/archit/Pictures/Wallpapers -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \\) | sort"]
                running: false
                stdout: SplitParser {
                    onRead: (line) => {
                        var trimmed = line.trim()
                        if (trimmed !== "") {
                            root.wallpapers = root.wallpapers.concat([trimmed])
                        }
                    }
                }
            }

            Process {
                id: symlinkResolver
                command: ["readlink", "-f", "/home/archit/Pictures/Wallpapers/current_wallpaper"]
                running: true
                stdout: SplitParser {
                    onRead: (line) => {
                        var resolved = line.trim()
                        if (resolved !== "") root.activeWallpaper = resolved
                    }
                }
            }

            property string pendingWallpaper: ""

            Process {
                id: symlinkWriter
                command: ["ln", "-sf", root.pendingWallpaper, "/home/archit/Pictures/Wallpapers/current_wallpaper"]
                running: false
                onRunningChanged: {
                    if (!running && root.pendingWallpaper !== "") {
                        hyprpaperPreload.running = true
                    }
                }
            }

            Process {
                id: hyprpaperPreload
                command: ["hyprctl", "hyprpaper", "preload", root.pendingWallpaper]
                running: false
                onRunningChanged: {
                    if (!running && root.pendingWallpaper !== "") {
                        hyprpaperApply.running = true
                    }
                }
            }

            Process {
                id: hyprpaperApply
                command: ["hyprctl", "hyprpaper", "wallpaper", "," + root.pendingWallpaper]
                running: false
                onRunningChanged: {
                    if (!running && root.pendingWallpaper !== "") {
                        root.activeWallpaper = root.pendingWallpaper
                        hyprpaperUnload.running = true
                        notifySend.running = true
                    }
                }
            }

            Process {
                id: hyprpaperUnload
                command: ["bash", "-c", "sleep 1 && hyprctl hyprpaper unload all"]
                running: false
            }

            Process {
                id: notifySend
                command: ["notify-send", "Wallpaper", "Applied: " + root.pendingWallpaper.split("/").pop()]
                running: false
            }

            function applyWallpaper(path) {
                root.pendingWallpaper = path
                symlinkWriter.running = true
            }

            screen: modelData
            visible: true
            color: "transparent"
            WlrLayershell.namespace: "quickshell:wallpaper-changer"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.wallpaperOpen
                ? WlrKeyboardFocus.Exclusive
                : WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            HyprlandFocusGrab {
                id: grab
                windows: [root]
                property bool canBeActive: root.monitorIsFocused
                active: false
                onCleared: () => {
                    if (!active) GlobalStates.wallpaperOpen = false
                }
            }

            Connections {
                target: GlobalStates
                function onWallpaperOpenChanged() {
                    if (GlobalStates.wallpaperOpen) {
                        root.isClosing = false
                        closingTimer.stop()
                        root.wallpapers = []
                        wallpaperScanner.running = true
                        symlinkResolver.running = true
                        focusTimer.start()
                        delayedGrabTimer.start()
                    } else {
                        grab.active = false
                        root.isClosing = true
                        closingTimer.restart()
                    }
                }
            }

            Timer {
                id: focusTimer
                interval: 150
                repeat: false
                onTriggered: searchInput.forceActiveFocus(Qt.OtherFocusReason)
            }

            Timer {
                id: delayedGrabTimer
                interval: 50
                repeat: false
                onTriggered: {
                    if (!grab.canBeActive) return
                    grab.active = GlobalStates.wallpaperOpen
                }
            }

            Rectangle {
                id: panelMask
                x: root.cardX
                y: (root.height - root.panelH) / 2
                width: root.panelW
                height: root.panelH
                visible: false
            }

            mask: Region {
                item: panelMask
            }

            MouseArea {
                anchors.fill: parent
                z: -1
                enabled: GlobalStates.wallpaperOpen
                onClicked: GlobalStates.wallpaperOpen = false
            }

            property var filteredWallpapers: {
                var q = root.searchQuery.toLowerCase().trim()
                if (q === "") return root.wallpapers
                return root.wallpapers.filter(w =>
                    w.split("/").pop().toLowerCase().includes(q)
                )
            }

            Rectangle {
                id: panelCard
                x: root.cardX
                y: (root.height - root.panelH) / 2
                width: root.panelW
                height: root.panelH
                color: "#000000"
                radius: 18
                clip: true

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1.5
                    z: 3
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.2; color: "#89b4fa" }
                        GradientStop { position: 0.8; color: "#cba6f7" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.07)
                    z: 4
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.wallpaperOpen = false
                        event.accepted = true
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: "󰸉"
                            font.family: "JetBrains Mono Nerd Font"
                            font.pixelSize: 18
                            color: "#89b4fa"
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            text: "Wallpapers"
                            font.family: "JetBrains Mono Nerd Font"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: "#ffffff"
                            verticalAlignment: Text.AlignVCenter
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            height: 22
                            width: countText.width + 16
                            radius: 11
                            color: Qt.rgba(0.54, 0.71, 0.98, 0.12)
                            border.width: 1
                            border.color: Qt.rgba(0.54, 0.71, 0.98, 0.25)

                            Text {
                                id: countText
                                anchors.centerIn: parent
                                text: root.filteredWallpapers.length + " wallpapers"
                                font.family: "JetBrains Mono Nerd Font"
                                font.pixelSize: 11
                                color: "#89b4fa"
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        color: Qt.rgba(1, 1, 1, 0.05)
                        radius: 9
                        border.width: 1
                        border.color: searchInput.activeFocus
                            ? Qt.rgba(0.54, 0.71, 0.98, 0.5)
                            : Qt.rgba(1, 1, 1, 0.08)
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Text {
                                text: ""
                                font.family: "JetBrains Mono Nerd Font"
                                font.pixelSize: 13
                                color: searchInput.activeFocus
                                    ? Qt.rgba(0.54, 0.71, 0.98, 0.8)
                                    : Qt.rgba(1, 1, 1, 0.3)
                                verticalAlignment: Text.AlignVCenter
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                color: "#ffffff"
                                font.family: "JetBrains Mono Nerd Font"
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                cursorVisible: activeFocus
                                selectByMouse: true
                                activeFocusOnPress: true

                                onTextChanged: root.searchQuery = text

                                Text {
                                    anchors.fill: parent
                                    text: "Search wallpapers..."
                                    color: Qt.rgba(1, 1, 1, 0.25)
                                    font.family: "JetBrains Mono Nerd Font"
                                    font.pixelSize: 12
                                    verticalAlignment: Text.AlignVCenter
                                    visible: searchInput.text === ""
                                }

                                Keys.onPressed: (event) => {
                                    if (event.key === Qt.Key_Escape) {
                                        GlobalStates.wallpaperOpen = false
                                        event.accepted = true
                                    }
                                }
                            }

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                color: Qt.rgba(1, 1, 1, 0.1)
                                visible: searchInput.text !== ""
                                opacity: clearHover.containsMouse ? 1.0 : 0.6
                                Behavior on opacity { NumberAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    font.pixelSize: 9
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: clearHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        searchInput.text = ""
                                        root.searchQuery = ""
                                        searchInput.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        GridView {
                            id: wallpaperGrid
                            width: parent.width
                            cellWidth:  (root.panelW - 28) / 4
                            cellHeight: cellWidth * 0.6 + 6

                            model: root.filteredWallpapers

                            delegate: Item {
                                width:  wallpaperGrid.cellWidth
                                height: wallpaperGrid.cellHeight

                                property string wallPath: root.filteredWallpapers[index] ?? ""
                                property bool isActive: wallPath === root.activeWallpaper

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    radius: 12
                                    color: "transparent"
                                    clip: true

                                    border.width: isActive ? 2 : 0
                                    border.color: "#89b4fa"
                                    Behavior on border.width { NumberAnimation { duration: 150 } }

                                    Image {
                                        id: thumb
                                        anchors.fill: parent
                                        anchors.margins: isActive ? 2 : 0
                                        source: wallPath !== "" ? "file://" + wallPath : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        smooth: true
                                        mipmap: true
                                        cache: true
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: thumb.width
                                                height: thumb.height
                                                radius: 10
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 10
                                            color: Qt.rgba(1, 1, 1, 0.04)
                                            visible: parent.status !== Image.Ready

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰸉"
                                                font.family: "JetBrains Mono Nerd Font"
                                                font.pixelSize: 20
                                                color: Qt.rgba(1, 1, 1, 0.15)
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: Qt.rgba(0, 0, 0, tileHover.containsMouse ? 0.25 : 0.0)
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }

                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 6
                                        width: 22; height: 22
                                        radius: 11
                                        color: "#89b4fa"
                                        visible: isActive
                                        opacity: isActive ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "✓"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: "#000000"
                                        }
                                    }

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: 28
                                        radius: 10
                                        color: Qt.rgba(0, 0, 0, 0.7)
                                        visible: tileHover.containsMouse
                                        clip: true

                                        Rectangle {
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            height: parent.radius
                                            color: parent.color
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            width: parent.width - 8
                                            text: wallPath.split("/").pop()
                                            font.family: "JetBrains Mono Nerd Font"
                                            font.pixelSize: 9
                                            color: "#ffffff"
                                            elide: Text.ElideMiddle
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                    }

                                    MouseArea {
                                        id: tileHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (wallPath !== "") {
                                                root.applyWallpaper(wallPath)
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
    }

    IpcHandler {
        target: "wallpaper"
        function toggle() { GlobalStates.wallpaperOpen = !GlobalStates.wallpaperOpen }
        function open()   { GlobalStates.wallpaperOpen = true }
        function close()  { GlobalStates.wallpaperOpen = false }
    }
}