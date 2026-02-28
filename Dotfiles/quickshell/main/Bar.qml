import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

Variants {
    id: root
    model: Quickshell.screens

    property var lastScrollTime: 0
    readonly property int scrollDelay: 150
    property bool wsHeld: false
    property bool clockHeld: false

    PanelWindow {
        id: surface
        screen: modelData
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-vertical-bar"
        WlrLayershell.exclusiveZone: 0

        anchors.left: true
        anchors.top: true
        anchors.bottom: true

        width: screen.width
        color: "transparent"

        Rectangle {
            id: maskExpander
            x: 0
            y: 0
            width: root.wsHeld ? surface.width : 0
            height: root.wsHeld ? surface.height : 0
            visible: false
        }

        mask: Region {
            item: wsModule
            Region { item: dateTimeModule }
            Region { item: maskExpander }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.wsHeld
            z: -1
            onClicked: root.wsHeld = false
        }

        // --- WORKSPACES MODULE ---
        Rectangle {
            id: wsModule
            width: 45
            height: wsLayout.height + 50
            anchors.verticalCenter: parent.verticalCenter
            color: "#000000"

            x: (wsHoverArea.containsMouse || root.wsHeld) ? 0 : -38.5

            radius: 0
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: wsModule.width
                    height: wsModule.height
                    radius: 10
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.radius
                        color: "black"
                    }
                }
            }

            Behavior on x { NumberAnimation { duration: 150 } }

            MouseArea {
                id: wsHoverArea
                width: 45
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                onEntered: root.wsHeld = true
                
                // Logic to switch between all 5 workspaces
                onWheel: (wheel) => {
                    let currentTime = Date.now()
                    if (currentTime - root.lastScrollTime >= root.scrollDelay) {
                        let currentId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
                        let nextId

                        if (wheel.angleDelta.y < 0) {
                            nextId = (currentId % 5) + 1
                        } else if (wheel.angleDelta.y > 0) {
                            nextId = (currentId - 2 + 5) % 5 + 1
                        }

                        if (nextId) {
                            Hyprland.dispatch(`workspace ${nextId}`)
                        }
                        root.lastScrollTime = currentTime
                    }
                }
            }

            ColumnLayout {
                id: wsLayout
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: -2.5
                anchors.verticalCenter: parent.verticalCenter
                spacing: 20
                opacity: (wsHoverArea.containsMouse || root.wsHeld) ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Repeater {
                    model: 5 
                    delegate: Rectangle {
                        readonly property int wsId: index + 1
                        readonly property bool isActive: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === wsId
                        
                        // Check if the workspace exists (has windows in the background)
                        readonly property bool hasWindows: {
                            for (let i = 0; i < Hyprland.workspaces.values.length; i++) {
                                if (Hyprland.workspaces.values[i].id === wsId) return true;
                            }
                            return false;
                        }
                        
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 15
                        implicitHeight: isActive ? 50 : 15
                        radius: 100
                        
                        Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        gradient: Gradient {
                            GradientStop { position: 0.0; color: (isActive || hasWindows) ? "#89b4fa" : Qt.rgba(0.53, 0.70, 0.98, 0.3) }
                            GradientStop { position: 1.0; color: (isActive || hasWindows) ? "#cba6f7" : Qt.rgba(0.79, 0.65, 0.96, 0.3) }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Hyprland.dispatch(`workspace ${wsId}`)
                        }
                    }
                }
            }
        }

        // --- UNIFIED DATE, TIME & MEDIA MODULE ---
        Rectangle {
            id: dateTimeModule
            width: 45
            height: bottomModule.implicitHeight + 60
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -15
            color: "#000000"

            x: (clockHoverArea.containsMouse || root.clockHeld) ? 0 : -38.5

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: dateTimeModule.width
                    height: dateTimeModule.height
                    radius: 10

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.radius
                        color: "black"
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: parent.radius
                        height: parent.radius
                        color: "black"
                    }
                }
            }

            Behavior on x { NumberAnimation { duration: 150 } }

            MouseArea {
                id: clockHoverArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onEntered: root.clockHeld = true
                onClicked: root.clockHeld = false
            }

            ColumnLayout {
                id: bottomModule
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: -2.5
                anchors.verticalCenter: parent.verticalCenter
                spacing: 15
                opacity: (clockHoverArea.containsMouse || root.clockHeld) ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 150 } }

                ColumnLayout {
                    spacing: 5
                    Layout.alignment: Qt.AlignHCenter

                    ColumnLayout {
                        spacing: 3
                        Layout.alignment: Qt.AlignHCenter
                        Repeater {
                            model: [Qt.formatDateTime(new Date(), "ddd"), Qt.formatDateTime(new Date(), "MMM")]
                            delegate: Item {
                                required property int index
                                required property var modelData
                                Layout.preferredWidth: 45
                                Layout.preferredHeight: 10
                                Text {
                                    id: labelText
                                    text: modelData.toUpperCase()
                                    font.family: "Fira Sans"
                                    font.pixelSize: index === 0 ? 13 : 16
                                    font.weight: Font.Bold
                                    anchors.centerIn: parent
                                    visible: false
                                }
                                LinearGradient {
                                    anchors.fill: labelText
                                    source: labelText
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "#89b4fa" }
                                        GradientStop { position: 1.0; color: "#cba6f7" }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 45
                        Layout.preferredHeight: 20
                        Text {
                            id: dayNumText
                            text: Qt.formatDateTime(new Date(), "dd")
                            font.family: "JetBrains Mono Nerd Font"
                            font.pixelSize: 23
                            font.weight: Font.Black
                            anchors.centerIn: parent
                            visible: false
                        }
                        LinearGradient {
                            anchors.fill: dayNumText
                            source: dayNumText
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#89b4fa" }
                                GradientStop { position: 1.0; color: "#cba6f7" }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 32.5; height: 2.5; radius: 10
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#89b4fa" }
                        GradientStop { position: 1.0; color: "#cba6f7" }
                    }
                }

                ColumnLayout {
                    id: clockContainer
                    spacing: 2.5
                    Layout.alignment: Qt.AlignHCenter
                    property string hours: (new Date().getHours() % 12 || 12).toString().padStart(2, '0')
                    property string mins: Qt.formatDateTime(new Date(), "mm")
                    property string sec: Qt.formatDateTime(new Date(), "ss")
                    Repeater {
                        model: ["hours", "mins", "sec"]
                        delegate: Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 45
                            Layout.preferredHeight: 25
                            Text {
                                id: timeText
                                text: clockContainer[modelData]
                                font.family: "JetBrains Mono Nerd Font"
                                font.pixelSize: 25
                                font.weight: Font.Bold
                                anchors.centerIn: parent
                                visible: false
                            }
                            LinearGradient {
                                anchors.fill: timeText
                                source: timeText
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#89b4fa" }
                                    GradientStop { position: 1.0; color: "#cba6f7" }
                                }
                            }
                        }
                    }
                }
            }

            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: {
                    let now = new Date()
                    clockContainer.hours = (now.getHours() % 12 || 12).toString().padStart(2, '0')
                    clockContainer.mins = Qt.formatDateTime(now, "mm")
                    clockContainer.sec = Qt.formatDateTime(now, "ss")
                }
            }
        }
    }
}