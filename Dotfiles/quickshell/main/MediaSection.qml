import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null

    function formatTime(secs) {
        if (!secs || secs <= 0) return "0:00"
        var s = Math.floor(secs)
        var m = Math.floor(s / 60)
        s = s % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    Timer {
        interval: 1000
        running: root.player?.isPlaying ?? false
        repeat: true
        onTriggered: if (root.player) root.player.positionChanged()
    }

    // ── NO PLAYER STATE ──
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12
        visible: !root.player

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰝚"
            font.family: "Material Design Icons"
            font.pixelSize: 64
            color: Qt.rgba(1, 1, 1, 0.08)
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Nothing playing"
            font.pixelSize: 13
            font.weight: Font.Medium
            color: Qt.rgba(1, 1, 1, 0.25)
            font.family: "JetBrains Mono Nerd Font"
        }
    }

    // ── ACTIVE PLAYER ──
    Item {
        anchors.fill: parent
        visible: !!root.player
        clip: true

        // --- BLURRED BACKGROUND ---
        Image {
            id: bgArt
            anchors.fill: parent
            source: root.player?.trackArtUrl ?? ""
            fillMode: Image.PreserveAspectCrop
            visible: false
            smooth: true
        }
        FastBlur {
            anchors.fill: bgArt
            source: bgArt
            radius: 50
            visible: bgArt.status === Image.Ready
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.55) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.82) }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: "#0d0d0f"
            visible: bgArt.status !== Image.Ready
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // --- TOP ROW: circular art + vertically centered info ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                // ── CIRCULAR ALBUM ART using OpacityMask ──
                Item {
                    width: 100
                    height: 100

                    // Glow ring
                    Rectangle {
                        anchors.centerIn: parent
                        width: 110; height: 110; radius: 55
                        color: "transparent"
                        border.width: 2
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        layer.enabled: true
                        layer.effect: Glow {
                            radius: 18; samples: 24; spread: 0.1
                            color: "#89b4fa"
                            transparentBorder: true
                        }
                    }

                    // Spin container
                    Item {
                        id: spinItem
                        anchors.centerIn: parent
                        width: 100; height: 100

                        RotationAnimator on rotation {
                            from: 0; to: 360
                            duration: 12000
                            loops: Animation.Infinite
                            running: root.player?.isPlaying ?? false
                            easing.type: Easing.Linear
                        }

                        // The actual image — hidden, used as OpacityMask source
                        Image {
                            id: artImg
                            anchors.fill: parent
                            source: root.player?.trackArtUrl ?? ""
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            visible: false
                        }

                        // Fallback dark circle background
                        Rectangle {
                            id: artBg
                            anchors.fill: parent
                            radius: 50
                            color: "#1a1a2e"
                            visible: false
                        }

                        // Circle mask shape
                        Rectangle {
                            id: circleMask
                            anchors.fill: parent
                            radius: 50
                            visible: false
                        }

                        // Apply OpacityMask — this FORCES the circle, no exceptions
                        OpacityMask {
                            anchors.fill: parent
                            source: artImg.status === Image.Ready ? artImg : artBg
                            maskSource: circleMask
                        }

                        // Fallback icon (shown when no art)
                        Text {
                            anchors.centerIn: parent
                            text: "󰎇"
                            font.family: "Material Design Icons"
                            font.pixelSize: 42
                            color: Qt.rgba(1, 1, 1, 0.2)
                            visible: artImg.status !== Image.Ready
                        }

                        // Center vinyl hole
                        Rectangle {
                            anchors.centerIn: parent
                            width: 14; height: 14; radius: 7
                            color: "#0d0d0f"
                            border.width: 2
                            border.color: Qt.rgba(1, 1, 1, 0.3)
                            visible: artImg.status === Image.Ready
                        }
                    }
                }

                // ── TRACK INFO — vertically centered next to art ──
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter   // center the whole column vertically
                    spacing: 6

                    // App/source name
                    Text {
                        text: root.player?.identity ?? ""
                        font.pixelSize: 16
                        font.family: "Fira Sans"
                        color: Qt.rgba(1, 1, 1, 0.35)
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: text !== ""
                    }

                    // Track title
                    Text {
                        Layout.fillWidth: true
                        text: root.player?.trackTitle ?? "Unknown Track"
                        font.pixelSize: 22
                        font.weight: Font.Bold
                        font.family: "Fira Sans"
                        color: "white"
                        elide: Text.ElideRight
                    }

                    // Artist
                    Text {
                        Layout.fillWidth: true
                        text: root.player?.trackArtist ?? "Unknown Artist"
                        font.pixelSize: 18
                        font.family: "Fira Sans"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        elide: Text.ElideRight
                    }

                    // Playing indicator dots
                    RowLayout {
                        spacing: 4
                        visible: root.player?.isPlaying ?? false
                        Repeater {
                            model: 4
                            delegate: Rectangle {
                                width: 3; radius: 2
                                color: index % 2 === 0 ? "#89b4fa" : "#cba6f7"
                                SequentialAnimation on height {
                                    loops: Animation.Infinite
                                    running: root.player?.isPlaying ?? false
                                    NumberAnimation { to: 16; duration: 300 + index * 80; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 4;  duration: 300 + index * 80; easing.type: Easing.InOutSine }
                                }
                                height: 4
                            }
                        }
                    }
                }
            }

            // --- SEEK BAR ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5

                Item {
                    Layout.fillWidth: true
                    height: 20

                    Rectangle {
                        id: seekTrack
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 4; radius: 2
                        color: Qt.rgba(1, 1, 1, 0.12)
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: seekTrack.left
                        width: root.player && root.player.length > 0
                            ? Math.min(1, root.player.position / root.player.length) * seekTrack.width
                            : 0
                        height: 4; radius: 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#89b4fa" }
                            GradientStop { position: 1.0; color: "#cba6f7" }
                        }
                        Behavior on width { SmoothedAnimation { duration: 800 } }
                    }

                    Rectangle {
                        id: seekThumb
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.player && root.player.length > 0
                            ? Math.min(1, root.player.position / root.player.length) * (seekTrack.width - width)
                            : 0
                        width: seekMA.containsMouse || seekMA.pressed ? 14 : 10
                        height: width; radius: width / 2
                        color: "white"
                        Behavior on x { SmoothedAnimation { duration: 800 } }
                        Behavior on width { NumberAnimation { duration: 100 } }
                        layer.enabled: true
                        layer.effect: Glow {
                            radius: 6; samples: 12; spread: 0.2
                            color: "#cba6f7"
                            transparentBorder: true
                        }
                    }

                    MouseArea {
                        id: seekMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: (mouse) => {
                            if (root.player && root.player.length > 0)
                                root.player.position = (mouse.x / width) * root.player.length
                        }
                        onPositionChanged: (mouse) => {
                            if (pressed && root.player && root.player.length > 0)
                                root.player.position = Math.max(0, Math.min(root.player.length, (mouse.x / width) * root.player.length))
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: root.formatTime(root.player?.position ?? 0)
                        font.pixelSize: 10; font.family: "JetBrains Mono Nerd Font"
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.formatTime(root.player?.length ?? 0)
                        font.pixelSize: 10; font.family: "JetBrains Mono Nerd Font"
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }
                }
            }

            // --- CONTROLS ---
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                Rectangle {
                    width: 42; height: 42; radius: 21
                    color: prevMA.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    Text {
                        anchors.centerIn: parent; text: "󰒮"
                        font.family: "Material Design Icons"; font.pixelSize: 20
                        color: Qt.rgba(1, 1, 1, 0.8)
                    }
                    MouseArea { id: prevMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.player?.previous() }
                }

                Rectangle {
                    width: 70; height: 42; radius: 21
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: playMA.containsMouse ? "#9ec5ff" : "#89b4fa" }
                        GradientStop { position: 1.0; color: playMA.containsMouse ? "#d4b0ff" : "#cba6f7" }
                    }
                    Behavior on implicitWidth { NumberAnimation { duration: 150 } }
                    layer.enabled: true
                    layer.effect: Glow {
                        radius: playMA.containsMouse ? 14 : 8
                        samples: 20; spread: 0.15
                        color: "#a0aaff"
                        transparentBorder: true
                        Behavior on radius { NumberAnimation { duration: 150 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root.player?.isPlaying ? "󰏤" : "󰐊"
                        font.family: "Material Design Icons"; font.pixelSize: 26
                        color: "#0d0d0f"
                    }
                    MouseArea { id: playMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.player?.togglePlaying() }
                }

                Rectangle {
                    width: 42; height: 42; radius: 21
                    color: nextMA.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    Text {
                        anchors.centerIn: parent; text: "󰒭"
                        font.family: "Material Design Icons"; font.pixelSize: 20
                        color: Qt.rgba(1, 1, 1, 0.8)
                    }
                    MouseArea { id: nextMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.player?.next() }
                }
            }
        }
    }
}