import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

PanelWindow {
    id: toastRoot
    required property NotificationServer notifServer
    property int activeToasts: 0

    visible: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors.bottom: true
    anchors.right: true
    
    // Ensure the window is wide enough for the 400px toasts + margins
    implicitWidth: 450
    // The window height will grow automatically with the column
    implicitHeight: Math.max(1, toastColumn.implicitHeight + 20)

    // Mask to allow clicks to pass through transparent areas
    mask: Region { item: toastColumn }

    Connections {
        target: toastRoot.notifServer
        function onNotification(n) {
            var component = Qt.createComponent("NotificationToast.qml")
            if (component.status === Component.Ready) {
                toastRoot.activeToasts++
                component.createObject(toastColumn, { 
                    "modelData": n,
                    "toastWindow": toastRoot 
                })
            }
        }
    }

    ColumnLayout {
        id: toastColumn
        width: 400
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 10
        anchors.bottomMargin: 10
        spacing: 12
        layoutDirection: Qt.BottomToTop
    }
}