import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../common"
import "../../services"
import "."

Scope {
    id: overviewScope
    Variants {
        id: overviewVariants
        model: Quickshell.screens
        PanelWindow {
            id: root
            required property var modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

            property bool overviewHeld: false
            property bool isClosing: false
            property bool ready: false

            Timer {
                id: closingTimer
                interval: 300
                repeat: false
                onTriggered: root.isClosing = false
            }

            property real contentY: {
                if (GlobalStates.overviewOpen || overviewHeld) return 0
                return -(columnLayout.implicitHeight - 7.5)
            }
            Behavior on contentY {
                enabled: root.ready
                NumberAnimation { duration: 300 }
            }

            Component.onCompleted: readyTimer.start()

            Timer {
                id: readyTimer
                interval: 100
                repeat: false
                onTriggered: root.ready = true
            }

            screen: modelData
            visible: true
            WlrLayershell.namespace: "quickshell:overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // ── MOVED TO LEFT EDGE ──
            Rectangle {
                id: peekStrip
                anchors.top: parent.top
                anchors.left: parent.left // Changed from horizontalCenter
                anchors.leftMargin: 0     // Added slight margin for aesthetics
                width: 150
                height: 5
                visible: false
            }

            Rectangle {
                id: maskExpander
                x: 0; y: 0
                width:  root.overviewHeld ? parent.width  : 0
                height: root.overviewHeld ? parent.height : 0
                visible: false
            }

            mask: Region {
                item: GlobalStates.overviewOpen ? keyHandler : peekStrip
                Region { item: maskExpander }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.overviewHeld && !GlobalStates.overviewOpen
                z: -1
                onClicked: {
                    root.isClosing = true
                    closingTimer.restart()
                    root.overviewHeld = false
                }
            }

            // ── MOVED HOVER AREA TO LEFT EDGE ──
            MouseArea {
                id: peekHoverArea
                anchors.top: parent.top
                anchors.left: parent.left // Changed from horizontalCenter
                anchors.leftMargin: 0
                width: 160               // Slightly wider for easier triggering at the corner
                height: 50
                hoverEnabled: true
                propagateComposedEvents: true
                z: 2
                onEntered: {
                    if (!GlobalStates.overviewOpen) {
                        HyprlandData.updateAll()
                        root.overviewHeld = true
                    }
                }
                onPressed: (mouse) => mouse.accepted = false
            }

            HyprlandFocusGrab {
                id: grab
                windows: [root]
                property bool canBeActive: root.monitorIsFocused
                active: false
                onCleared: () => {
                    if (!active) GlobalStates.overviewOpen = false
                }
            }

            Connections {
                target: GlobalStates
                function onOverviewOpenChanged() {
                    if (GlobalStates.overviewOpen) {
                        root.isClosing = false
                        closingTimer.stop()
                        root.overviewHeld = false
                        HyprlandData.updateAll()
                        delayedGrabTimer.start()
                    } else {
                        grab.active = false
                        root.isClosing = true
                        closingTimer.restart()
                    }
                }
            }

            Timer {
                id: delayedGrabTimer
                interval: Config.options.hacks.arbitraryRaceConditionDelay
                repeat: false
                onTriggered: {
                    if (!grab.canBeActive) return;
                    grab.active = GlobalStates.overviewOpen;
                }
            }

            implicitWidth: columnLayout.implicitWidth
            implicitHeight: columnLayout.implicitHeight

            Item {
                id: keyHandler
                anchors.fill: parent
                visible: GlobalStates.overviewOpen
                focus: GlobalStates.overviewOpen

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return) {
                        GlobalStates.overviewOpen = false;
                        event.accepted = true;
                        return;
                    }

                    const workspacesPerGroup = 5;
                    const currentId = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1;
                    const currentGroup = Math.floor((currentId - 1) / workspacesPerGroup);
                    const minWorkspaceId = currentGroup * workspacesPerGroup + 1;
                    const maxWorkspaceId = minWorkspaceId + workspacesPerGroup - 1;

                    let targetId = null;
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        targetId = currentId - 1;
                        if (targetId < minWorkspaceId) targetId = maxWorkspaceId;
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        targetId = currentId + 1;
                        if (targetId > maxWorkspaceId) targetId = minWorkspaceId;
                    } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
                        const position = event.key - Qt.Key_0;
                        targetId = minWorkspaceId + position - 1;
                    }

                    if (targetId !== null) {
                        Hyprland.dispatch("workspace " + targetId);
                        event.accepted = true;
                    }
                }
            }

            ColumnLayout {
                id: columnLayout
                anchors.left: parent.left
                anchors.leftMargin: 0
                y: root.contentY
                spacing: 0

                Loader {
                    id: overviewLoader
                    active: true
                    sourceComponent: OverviewWidget {
                        panelWindow: root
                        visible: GlobalStates.overviewOpen || root.overviewHeld || root.isClosing
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 5

                    // Visual Pill Indicator
                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        width: 250
                        height: 50
                        color: "#000000"

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: 250
                                height: 50
                                radius: 10
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    height: parent.radius
                                    color: "black"
                                }
                            }
                        }

                        opacity: (!root.overviewHeld && !GlobalStates.overviewOpen && !root.isClosing) ? 1.0 : 0.0
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "overview"
        function toggle() { GlobalStates.overviewOpen = !GlobalStates.overviewOpen; }
        function close() { GlobalStates.overviewOpen = false; }
        function open() { GlobalStates.overviewOpen = true; }
    }
}