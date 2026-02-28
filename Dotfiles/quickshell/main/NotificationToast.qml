import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Qt5Compat.GraphicalEffects

Item {
    id: root
    required property var modelData
    property var toastWindow: null

    property bool isVisible: true
    property bool isHovered: false
    property bool isDragging: false
    property real dragX: 0
    property bool showingReply: false

    readonly property bool isWhatsApp: modelData.appName.toLowerCase().includes("whatsapp")

    readonly property color accentColor: {
        var app = modelData.appName.toLowerCase()
        if (app.includes("whatsapp"))  return "#25d366"
        if (app.includes("discord"))   return "#5865f2"
        if (app.includes("spotify"))   return "#1db954"
        if (app.includes("firefox"))   return "#ff7139"
        if (app.includes("chrome"))    return "#4285f4"
        if (app.includes("telegram"))  return "#2ca5e0"
        if (app.includes("gmail") || app.includes("mail")) return "#ea4335"
        if (app.includes("slack"))     return "#e01e5a"
        if (app.includes("youtube"))   return "#ff0000"
        return "#cba6f7"
    }

    width: 400
    // Use implicitHeight so ColumnLayout tracks it for the mask
    implicitHeight: cardBg.implicitHeight + (showingReply ? replyArea.implicitHeight + 8 : 0) + 15
    height: implicitHeight
    opacity: 0
    x: dragX
    clip: true

    Component.onCompleted: entranceAnim.start()

    SequentialAnimation {
        id: entranceAnim
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "opacity"
                from: 0; to: 1; duration: 350
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root; property: "dragX"
                from: 120; to: 0; duration: 400
                easing.type: Easing.OutQuint
            }
            NumberAnimation {
                target: cardBg; property: "scale"
                from: 0.92; to: 1.0; duration: 400
                easing.type: Easing.OutQuint
            }
        }
    }

    function dismiss() {
        if (!isVisible) return
        isVisible = false
        
        // --- VIBRATION FIX ---
        // By assigning the height to itself, we break the binding loop. 
        // This stops the "formula" from fighting the exit animation.
        var currentH = root.implicitHeight
        root.implicitHeight = currentH 
        
        entranceAnim.stop()
        snapBack.stop()
        exitAnim.start()
    }

    SequentialAnimation {
        id: exitAnim
        // 1. Smoothly fade and slide out first (Gentle exit)
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: 250; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "dragX"; to: 80; duration: 300; easing.type: Easing.OutCubic }
        }
        // 2. Collapse the layout height (Now perfectly smooth)
        NumberAnimation { target: root; property: "implicitHeight"; to: 0; duration: 300; easing.type: Easing.InOutQuart }
        
        ScriptAction {
            script: {
                modelData.close()
                if (toastWindow) toastWindow.activeToasts = Math.max(0, toastWindow.activeToasts - 1)
                root.destroy()
            }
        }
    }

    // --- OUTER GLOW ---
    Rectangle {
        anchors.fill: cardBg
        anchors.margins: -1
        radius: cardBg.radius + 1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, isHovered ? 0.6 : 0.25)
        Behavior on border.color { ColorAnimation { duration: 200 } }

        layer.enabled: true
        layer.effect: Glow {
            radius: isHovered ? 14 : 6
            samples: 24
            spread: 0.1
            color: root.accentColor
            transparentBorder: true
            Behavior on radius { NumberAnimation { duration: 200 } }
        }
    }

    // --- MAIN CARD ---
    Rectangle {
        id: cardBg
        width: parent.width
        implicitHeight: innerColumn.implicitHeight + 20
        radius: 18
        color: Qt.rgba(0.07, 0.07, 0.11, 0.92)
        transformOrigin: Item.Right

        border.width: 1
        border.color: Qt.rgba(1, 1, 1, isHovered ? 0.12 : 0.06)
        Behavior on border.color { ColorAnimation { duration: 200 } }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: cardBg.width; height: cardBg.height; radius: cardBg.radius
            }
        }

        // Top shimmer line
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: 1
            radius: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, 0.15) }
                GradientStop { position: 0.7; color: Qt.rgba(1, 1, 1, 0.15) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Accent left bar
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: progressTrack.top
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            width: 3
            radius: 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.accentColor }
                GradientStop { position: 1.0; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.2) }
            }
        }

        // Drag + hover handler
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            propagateComposedEvents: true
            onEntered: root.isHovered = true
            onExited:  root.isHovered = false
            onPressed: (mouse) => { root.isDragging = true; mouse.accepted = false }
            onReleased: {
                root.isDragging = false
                if (root.dragX > 80) dismiss()
                else snapBack.start()
            }
            onPositionChanged: (mouse) => {
                if (pressed && mouse.x > 0) root.dragX = Math.max(0, root.dragX + mouse.x - width / 2)
            }
        }

        ColumnLayout {
            id: innerColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            anchors.topMargin: 14
            spacing: 10

            // --- HEADER ROW ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item {
                    width: 42; height: 42

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4)
                    }

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: modelData.image
                            ? (modelData.image.startsWith("/") ? "file://" + modelData.image : modelData.image)
                            : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle { width: 38; height: 38; radius: 10 }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "ｚ"
                        font.family: "Material Design Icons"
                        font.pixelSize: 20
                        color: root.accentColor
                        visible: !modelData.image || modelData.image === ""
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: modelData.summary !== "" ? modelData.summary : "Notification"
                        color: "#ffffff"
                        font.weight: Font.DemiBold
                        font.pixelSize: 13
                        font.family: "Fira Sans"
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        spacing: 4
                        Rectangle { width: 6; height: 6; radius: 3; color: root.accentColor }
                        Text {
                            text: modelData.appName
                            color: root.accentColor
                            font.pixelSize: 10
                            font.family: "JetBrains Mono Nerd Font"
                            font.weight: Font.Medium
                        }
                    }
                }

                ColumnLayout {
                    spacing: 4
                    Layout.alignment: Qt.AlignTop
                    Rectangle {
                        width: 20; height: 20; radius: 10
                        color: closeMA.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: "󰅖" 
                            color: Qt.rgba(1,1,1, closeMA.containsMouse ? 0.7 : 0.3)
                            font.pixelSize: 12
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        MouseArea {
                            id: closeMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dismiss()
                        }
                    }
                }
            }

            // --- BODY ---
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                text: modelData.body
                color: Qt.rgba(1, 1, 1, 0.6)
                wrapMode: Text.Wrap
                font.pixelSize: 12
                font.family: "Fira Sans"
                visible: modelData.body !== ""
                lineHeight: 1.3
            }

            // --- ACTION BUTTONS (WhatsApp only) ---
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 2
                spacing: 6
                visible: root.isWhatsApp

                Rectangle {
                    Layout.fillWidth: true; height: 28; radius: 8
                    color: replyBtnMA.containsMouse
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
                        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                    border.width: 1
                    border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: "昆  Reply"
                        color: root.accentColor
                        font.pixelSize: 11
                        font.family: "Fira Sans"
                    }
                    MouseArea {
                        id: replyBtnMA
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: { root.showingReply = !root.showingReply; if (root.showingReply) replyInput.forceActiveFocus() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 28; radius: 8
                    color: markReadMA.containsMouse ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04)
                    border.width: 1
                    border.color: Qt.rgba(1,1,1,0.08)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: "┫  Mark Read"
                        color: Qt.rgba(1,1,1,0.5)
                        font.pixelSize: 11
                        font.family: "Fira Sans"
                    }
                    MouseArea {
                        id: markReadMA
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: { modelData.invokeAction("default"); dismiss() }
                    }
                }
            }

            // --- REPLY BOX ---
            Rectangle {
                id: replyArea
                Layout.fillWidth: true
                implicitHeight: visible ? 36 : 0
                color: Qt.rgba(1,1,1,0.05)
                radius: 10
                visible: root.showingReply
                border.width: 1
                border.color: replyInput.activeFocus
                    ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.7)
                    : Qt.rgba(1,1,1,0.08)
                Behavior on border.color { ColorAnimation { duration: 150 } }
                Layout.bottomMargin: 2

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 6
                    spacing: 6

                    TextInput {
                        id: replyInput
                        Layout.fillWidth: true
                        color: "white"
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12
                        font.family: "Fira Sans"
                        onAccepted: {
                            if (text.trim() !== "") {
                                modelData.invokeAction("inline-reply")
                                dismiss()
                            }
                        }
                    }

                    Rectangle {
                        width: 24; height: 24; radius: 8
                        color: sendMA.containsMouse
                            ? root.accentColor
                            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.3)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: "抽"
                            font.family: "Material Design Icons"
                            font.pixelSize: 13
                            color: "white"
                        }
                        MouseArea {
                            id: sendMA
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: {
                                if (replyInput.text.trim() !== "") {
                                    modelData.invokeAction("inline-reply")
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- PROGRESS BAR ---
        Rectangle {
            id: progressTrack
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 3
            anchors.rightMargin: 3
            anchors.bottomMargin: 3
            height: 0
            radius: 1
            color: Qt.rgba(1,1,1,0.06)

            Rectangle {
                id: progressFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: 1
                width: parent.width
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.accentColor }
                    GradientStop { position: 1.0; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4) }
                }

                NumberAnimation on width {
                    from: progressFill.parent.width
                    to: 0
                    duration: 5000
                    running: !root.isHovered && root.isVisible && !root.showingReply
                    onFinished: if (root.isVisible) dismiss()
                }
            }
        }
    }

    // Smoother drag-back
    NumberAnimation {
        id: snapBack
        target: root; property: "dragX"; to: 0; duration: 300
        easing.type: Easing.OutCubic 
    }
}