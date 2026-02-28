import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: launcherScope

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: root
            required property var modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

            property bool launcherHeld: false
            property bool isClosing: false
            property bool ready: false
            property int selectedIndex: 0
            property string searchQuery: ""

            property string currentWallpaperPath: ""

            readonly property int launcherW: 500
            readonly property int launcherH: 600

            property real cardY: GlobalStates.launcherOpen 
                ? (root.height - root.launcherH) / 2 
                : (root.launcherHeld ? root.height - root.launcherH - 250 : root.height)
            
            Behavior on cardY {
                enabled: root.ready
                NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
            }

            Component.onCompleted: {
                readyTimer.start()
                wallpaperResolver.running = true
                wallpaperWatcher.start()
            }

            Timer {
                id: readyTimer
                interval: 1
                repeat: false
                onTriggered: root.ready = true
            }

            Timer {
                id: closingTimer
                interval: 1
                repeat: false
                onTriggered: root.isClosing = false
            }

            Timer {
                id: wallpaperWatcher
                interval: 1
                repeat: true
                running: false
                onTriggered: wallpaperResolver.running = true
            }

            Process {
                id: wallpaperResolver
                command: ["readlink", "-f", "/home/archit/Pictures/Wallpapers/current_wallpaper"]
                running: false
                stdout: SplitParser {
                    onRead: (line) => {
                        var resolved = line.trim()
                        if (resolved !== "" && resolved !== root.currentWallpaperPath) {
                            root.currentWallpaperPath = resolved
                            wallpaperImage.source = ""
                            wallpaperImage.source = "file://" + resolved
                        }
                    }
                }
            }

            screen: modelData
            visible: true
            color: "transparent"
            WlrLayershell.namespace: "quickshell:launcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.launcherOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Rectangle {
                id: peekStrip
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: 500
                height: 5
                visible: false
            }

            Rectangle {
                id: openMask
                x: (parent.width - root.launcherW) / 2
                y: root.cardY
                width: root.launcherW
                height: root.launcherH
                visible: false
            }

            Rectangle {
                id: maskExpander
                x: 0; y: 0
                width:  root.launcherHeld ? parent.width  : 0
                height: root.launcherHeld ? parent.height : 0
                visible: false
            }

            mask: Region {
                item: GlobalStates.launcherOpen ? openMask : peekStrip
                Region { item: maskExpander }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.launcherHeld && !GlobalStates.launcherOpen
                z: -1
                onClicked: {
                    root.isClosing = true
                    closingTimer.restart()
                    root.launcherHeld = false
                }
            }

            MouseArea {
                id: peekHoverArea
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: 500
                height: 10
                hoverEnabled: true
                propagateComposedEvents: true
                z: 2
                onEntered: {
                    if (!GlobalStates.launcherOpen) root.launcherHeld = true
                }
                onPressed: (mouse) => mouse.accepted = false
            }

            HyprlandFocusGrab {
                id: grab
                windows: [root]
                property bool canBeActive: root.monitorIsFocused
                active: false
                onCleared: () => {
                    if (!active) GlobalStates.launcherOpen = false
                }
            }

            Connections {
                target: GlobalStates
                function onLauncherOpenChanged() {
                    if (GlobalStates.launcherOpen) {
                        root.isClosing = false
                        closingTimer.stop()
                        root.launcherHeld = false
                        root.selectedIndex = 0
                        root.searchQuery = ""
                        searchInput.text = ""
                        delayedGrabTimer.start()
                        focusSearchTimer.start()
                    } else {
                        grab.active = false
                        root.isClosing = true
                        closingTimer.restart()
                    }
                }
            }

            Timer {
                id: focusSearchTimer
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
                    grab.active = GlobalStates.launcherOpen
                }
            }

            property var allApps: {
                var apps = []
                var entries = DesktopEntries.applications.values
                for (var i = 0; i < entries.length; i++) {
                    var e = entries[i]
                    if (!e || !e.name || e.name === "") continue
                    if (e.noDisplay) continue
                    if (e.onlyShowIn && e.onlyShowIn !== "") continue
                    apps.push(e)
                }
                apps.sort((a, b) => a.name.localeCompare(b.name))
                return apps
            }

            property var filteredApps: {
                var q = root.searchQuery.toLowerCase().trim()
                if (q === "") return allApps
                return allApps.filter(a => a.name.toLowerCase().includes(q))
            }

            Item {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: 500
                height: 7.5
                z: 10

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    y: -(50 - 50)
                    width: 500
                    height: 50
                    color: "#000000"

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: 500; height: 50; radius: 10
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: parent.radius
                                color: "black"
                            }
                        }
                    }

                    opacity: (!root.launcherHeld && !GlobalStates.launcherOpen && !root.isClosing) ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
            }

            Rectangle {
                id: launcherCard
                x: (parent.width - root.launcherW) / 2
                y: root.cardY
                width: root.launcherW
                height: root.launcherH
                color: "#000000"
                radius: 15
                clip: true

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1.5; z: 3
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

                focus: false
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onPressed: (mouse) => {
                        searchInput.forceActiveFocus(Qt.MouseFocusReason)
                        mouse.accepted = false
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 200
                        Layout.topMargin: 10
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10

                        Rectangle {
                            anchors.fill: parent
                            radius: 50
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#1a1a2e" }
                                GradientStop { position: 1.0; color: "#16213e" }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 50
                            clip: true
                            color: "transparent"

                            Image {
                                id: wallpaperImage
                                anchors.fill: parent
                                source: ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: false
                                cache: false
                                smooth: true
                                mipmap: true
                                visible: status === Image.Ready
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 5
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: "#0a0a0a" }
                            }
                        }
                    }

                    ListView {
                        id: appList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.topMargin: 6
                        Layout.bottomMargin: 6
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        spacing: 2
                        clip: true
                        model: root.filteredApps
                        currentIndex: root.selectedIndex

                        onCurrentIndexChanged: {
                            positionViewAtIndex(currentIndex, ListView.Contain)
                        }

                        delegate: Rectangle {
                            id: appItem
                            required property var modelData
                            required property int index

                            width: appList.width
                            height: 50
                            radius: 10
                            color: appItem.index === root.selectedIndex
                                ? Qt.rgba(1, 1, 1, 0.09)
                                : hoverMA.containsMouse
                                    ? Qt.rgba(1, 1, 1, 0.05)
                                    : "transparent"
                            Behavior on color { ColorAnimation { duration: 80 } }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: 10
                                anchors.bottomMargin: 10
                                anchors.leftMargin: 5
                                width: 2.5; radius: 2
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#89b4fa" }
                                    GradientStop { position: 1.0; color: "#cba6f7" }
                                }
                                visible: appItem.index === root.selectedIndex
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 14

                                Item {
                                    Layout.alignment: Qt.AlignVCenter
                                    width: 36; height: 36

                                    readonly property bool isIdleApp: {
                                        var name = appItem.modelData.name ?? ""
                                        var icon = appItem.modelData.icon ?? ""
                                        return (name === "IDLE" || name.startsWith("IDLE ") ||
                                                icon === "idle" || icon === "idle3")
                                    }

                                    // Your Python icon embedded as base64 — no icon theme needed
                                    Image {
                                        anchors.fill: parent
                                        visible: parent.isIdleApp
                                        source: "data:image/png;base64,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"
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        mipmap: true
                                    }

                                    Image {
                                        id: appIcon
                                        anchors.fill: parent
                                        visible: !parent.isIdleApp && status === Image.Ready
                                        sourceSize: Qt.size(72, 72)
                                        source: parent.isIdleApp ? "" : Quickshell.iconPath(
                                            appItem.modelData.icon ?? "application-x-executable",
                                            "application-x-executable"
                                        )
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        smooth: true
                                        mipmap: true
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 8
                                        visible: !parent.isIdleApp && appIcon.status !== Image.Ready
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: Qt.rgba(0.54, 0.71, 0.98, 0.25) }
                                            GradientStop { position: 1.0; color: Qt.rgba(0.79, 0.65, 0.97, 0.25) }
                                        }
                                        border.width: 1
                                        border.color: Qt.rgba(0.54, 0.71, 0.98, 0.3)

                                        Text {
                                            anchors.centerIn: parent
                                            text: (appItem.modelData.name ?? "?").charAt(0).toUpperCase()
                                            color: "#89b4fa"
                                            font.pixelSize: 15
                                            font.weight: Font.Bold
                                            font.family: "JetBrains Mono Nerd Font"
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: appItem.modelData.name ?? ""
                                    color: appItem.index === root.selectedIndex
                                        ? "#ffffff"
                                        : Qt.rgba(1, 1, 1, 0.80)
                                    font.family: "JetBrains Mono Nerd Font"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }
                            }

                            MouseArea {
                                id: hoverMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selectedIndex = appItem.index
                                onClicked: {
                                    appItem.modelData.execute()
                                    GlobalStates.launcherOpen = false
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        Layout.bottomMargin: 12
                        color: Qt.rgba(1, 1, 1, 0.05)
                        radius: 9
                        border.width: 1
                        border.color: searchInput.activeFocus
                            ? Qt.rgba(0.54, 0.71, 0.98, 0.55)
                            : Qt.rgba(1, 1, 1, 0.08)
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 10

                            Text {
                                text: ""
                                font.family: "JetBrains Mono Nerd Font"
                                font.pixelSize: 14
                                color: searchInput.activeFocus
                                    ? Qt.rgba(0.54, 0.71, 0.98, 0.8)
                                    : Qt.rgba(1, 1, 1, 0.3)
                                verticalAlignment: Text.AlignVCenter
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                verticalAlignment: Text.AlignVCenter
                                color: "#ffffff"
                                font.family: "JetBrains Mono Nerd Font"
                                font.pixelSize: 13
                                cursorVisible: activeFocus
                                selectByMouse: true
                                activeFocusOnPress: true

                                Text {
                                    anchors.fill: parent
                                    text: "Search applications..."
                                    color: Qt.rgba(1, 1, 1, 0.25)
                                    font.family: "JetBrains Mono Nerd Font"
                                    font.pixelSize: 13
                                    verticalAlignment: Text.AlignVCenter
                                    visible: searchInput.text === ""
                                }

                                onTextChanged: {
                                    root.searchQuery = text
                                    root.selectedIndex = 0
                                }

                                Keys.onPressed: (event) => {
                                    if (event.key === Qt.Key_Escape) {
                                        GlobalStates.launcherOpen = false
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Down) {
                                        root.selectedIndex = Math.min(root.selectedIndex + 1, root.filteredApps.length - 1)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Up) {
                                        root.selectedIndex = Math.max(root.selectedIndex - 1, 0)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        if (root.filteredApps.length > 0) {
                                            var app = root.filteredApps[root.selectedIndex]
                                            if (app) {
                                                app.execute()
                                                GlobalStates.launcherOpen = false
                                            }
                                        }
                                        event.accepted = true
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
        target: "launcher"
        function toggle() { GlobalStates.launcherOpen = !GlobalStates.launcherOpen }
        function open()   { GlobalStates.launcherOpen = true }
        function close()  { GlobalStates.launcherOpen = false }
    }
}