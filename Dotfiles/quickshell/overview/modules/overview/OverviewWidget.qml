import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../common"
import "../../common/functions"
import "../../common/widgets"
import "../../services"
import "."

Item {
    id: root
    required property var panelWindow
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
    readonly property var toplevels: ToplevelManager.toplevels
    readonly property int workspacesShown: (Config?.options.overview.rows ?? 2) * (Config?.options.overview.columns ?? 3)
    readonly property int workspaceGroup: Math.floor(((monitor?.activeWorkspace?.id ?? 1) - 1) / workspacesShown)
    property bool monitorIsFocused: (Hyprland.focusedMonitor?.name == monitor?.name)
    property var windows: HyprlandData.windowList
    property var windowByAddress: HyprlandData.windowByAddress
    property var windowAddresses: HyprlandData.addresses
    property var monitorData: HyprlandData.monitors.find(m => m.id === root.monitor?.id)
    property real scale: Config?.options.overview.scale ?? 1.0
 
    property color activeBorderColor: Appearance.colors.colSecondary

    property real workspaceImplicitWidth: (monitorData?.transform % 2 === 1) ?
        ((monitor.height / monitor.scale - (monitorData?.reserved?.[0] ?? 0) - (monitorData?.reserved?.[2] ?? 0)) * root.scale) :
        ((monitor.width / monitor.scale - (monitorData?.reserved?.[0] ?? 0) - (monitorData?.reserved?.[2] ?? 0)) * root.scale)
    property real workspaceImplicitHeight: (monitorData?.transform % 2 === 1) ?
        ((monitor.width / monitor.scale - (monitorData?.reserved?.[1] ?? 0) - (monitorData?.reserved?.[3] ?? 0)) * root.scale) :
        ((monitor.height / monitor.scale - (monitorData?.reserved?.[1] ?? 0) - (monitorData?.reserved?.[3] ?? 0)) * root.scale)

    property real workspaceNumberMargin: 100
    property real workspaceNumberSize: 250 * monitor.scale
    property int workspaceZ: 0
    property int windowZ: 1
    property int windowDraggingZ: 99999
    property real workspaceSpacing: 7.5

    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1

    property var rowsWithContent: {
        if (!Config?.options.overview.hideEmptyRows) return null;
        let rows = new Set();
        const firstWorkspace = root.workspaceGroup * root.workspacesShown + 1;
        const lastWorkspace = (root.workspaceGroup + 1) * root.workspacesShown;
        
        const currentWorkspace = monitor.activeWorkspace?.id ?? 1;
        if (currentWorkspace >= firstWorkspace && currentWorkspace <= lastWorkspace) {
            rows.add(Math.floor((currentWorkspace - firstWorkspace) / (Config?.options.overview.columns ?? 3)));
        }
        
        for (let addr in windowByAddress) {
            const win = windowByAddress[addr];
            const wsId = win?.workspace?.id;
            if (wsId >= firstWorkspace && wsId <= lastWorkspace) {
                const rowIndex = Math.floor((wsId - firstWorkspace) / (Config?.options.overview.columns ?? 3));
                rows.add(rowIndex);
            }
        }
        return rows;
    }

    implicitWidth: overviewBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: overviewBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

    property Component windowComponent: OverviewWindow {}
    property list<OverviewWindow> windowWidgets: []

    StyledRectangularShadow {
        target: overviewBackground
    }

    Rectangle { // Background
        id: overviewBackground
        property real padding: 11
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin

        implicitWidth: workspaceColumnLayout.implicitWidth + padding * 2
        implicitHeight: workspaceColumnLayout.implicitHeight + padding * 2
        radius: 0
        
        color: Qt.rgba(0.04, 0.04, 0.06, 0.97)
        border.width: 0
        border.color: Appearance.colors.colLayer0Border
        clip: true

        // Square top corners
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.radius
            color: parent.color
            visible: parent.radius > 0
            z: 10
        }

        // Gradient accent line at top edge
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 2
            z: 3
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;  color: "transparent" }
                GradientStop { position: 0.15; color: "#89b4fa" }
                GradientStop { position: 0.85; color: "#cba6f7" }
                GradientStop { position: 1.0;  color: "transparent" }
            }
        }

        // Subtle inner glow below top edge
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 48
            z: 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.54, 0.71, 0.98, 0.05) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        ColumnLayout { // Workspaces
            id: workspaceColumnLayout
            z: root.workspaceZ
            anchors.centerIn: parent
            spacing: workspaceSpacing
            Repeater {
                model: Config?.options.overview.rows ?? 2
                delegate: RowLayout {
                    id: row
                    property int rowIndex: index
                    spacing: workspaceSpacing
                    visible: !Config?.options.overview.hideEmptyRows || (root.rowsWithContent && root.rowsWithContent.has(rowIndex))
                    height: visible ? implicitHeight : 0

                    Repeater {
                        model: Config?.options.overview.columns ?? 3
                        Rectangle { // Workspace card
                            id: workspace
                            property int colIndex: index
                            property int workspaceValue: root.workspaceGroup * workspacesShown + rowIndex * (Config?.options.overview.columns ?? 3) + colIndex + 1
                            property bool isActive: (monitor?.activeWorkspace?.id ?? 1) === workspaceValue
                            property bool wsHovered: false

                            property color defaultWorkspaceColor: ColorUtils.transparentize(Appearance.colors.colLayer1, 1)
                            property color hoveredWorkspaceColor: ColorUtils.mix(defaultWorkspaceColor, Appearance.colors.colLayer1Hover, 0.2)
                            property color hoveredBorderColor: Appearance.colors.colLayer2Hover
                            property bool hoveredWhileDragging: false

                            implicitWidth: root.workspaceImplicitWidth
                            implicitHeight: root.workspaceImplicitHeight
                            color: hoveredWhileDragging ? hoveredWorkspaceColor : defaultWorkspaceColor
                            radius: Appearance.rounding.screenRounding * root.scale
                            border.width: isActive ? 2 : (hoveredWhileDragging ? 2 : 1)
                            border.color: hoveredWhileDragging ? hoveredBorderColor :
                                          isActive ? "transparent" :
                                          Qt.rgb(255, 255, 255)
                            clip: true

                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            scale: wsHovered && !hoveredWhileDragging ? 1.015 : 1.0

                            // Wallpaper
                            Image {
                                id: workspaceWallpaper
                                anchors.fill: parent
                                source: "file:///home/archit/Pictures/Wallpapers/current_wallpaper"
                                fillMode: Image.PreserveAspectCrop
                                opacity: 0.75
                            }

                            // Darken overlay
                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(0, 0, 0, workspace.wsHovered ? 0.12 : 0.28)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            // Active gradient border
                            Item {
                                anchors.fill: parent
                                visible: workspace.isActive
                                z: 2
                                Rectangle {
                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                    height: 2
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "#89b4fa" }
                                        GradientStop { position: 1.0; color: "#cba6f7" }
                                    }
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                                    height: 2
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "#89b4fa" }
                                        GradientStop { position: 1.0; color: "#cba6f7" }
                                    }
                                }
                                Rectangle {
                                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                    width: 2
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "#89b4fa" }
                                        GradientStop { position: 1.0; color: "#cba6f7" }
                                    }
                                }
                                Rectangle {
                                    anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                                    width: 2
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "#cba6f7" }
                                        GradientStop { position: 1.0; color: "#89b4fa" }
                                    }
                                }
                            }

                            // Workspace number
                            StyledText {
                                anchors.centerIn: parent
                                text: workspaceValue
                                font {
                                    pixelSize: root.workspaceNumberSize * root.scale
                                    weight: Font.Bold
                                    family: Appearance.font.family.expressive
                                }
                                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            // Hover shimmer
                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(1, 1, 1, workspace.wsHovered && !hoveredWhileDragging ? 0.04 : 0)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: workspaceArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                onEntered: workspace.wsHovered = true
                                onExited:  workspace.wsHovered = false
                                onClicked: {
                                    if (root.draggingTargetWorkspace === -1) {
                                        GlobalStates.overviewOpen = false
                                        Hyprland.dispatch(`workspace ${workspaceValue}`)
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: {
                                    root.draggingTargetWorkspace = workspaceValue
                                    if (root.draggingFromWorkspace == root.draggingTargetWorkspace) return;
                                    hoveredWhileDragging = true
                                }
                                onExited: {
                                    hoveredWhileDragging = false
                                    if (root.draggingTargetWorkspace == workspaceValue) root.draggingTargetWorkspace = -1
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { // Windows Space
            id: windowSpace
            anchors.centerIn: parent
            implicitWidth: workspaceColumnLayout.implicitWidth
            implicitHeight: workspaceColumnLayout.implicitHeight

            Repeater {
                model: ScriptModel {
                    values: {
                        return ToplevelManager.toplevels.values.filter((toplevel) => {
                            const address = `0x${toplevel.HyprlandToplevel.address}`
                            var win = windowByAddress[address]
                            const inWorkspaceGroup = (root.workspaceGroup * root.workspacesShown < win?.workspace?.id && win?.workspace?.id <= (root.workspaceGroup + 1) * root.workspacesShown)
                            return inWorkspaceGroup;
                        }).sort((a, b) => {
                            const addrA = `0x${a.HyprlandToplevel.address}`
                            const addrB = `0x${b.HyprlandToplevel.address}`
                            const winA = windowByAddress[addrA]
                            const winB = windowByAddress[addrB]
                            if (winA?.pinned !== winB?.pinned) return winA?.pinned ? 1 : -1
                            if (winA?.floating !== winB?.floating) return winA?.floating ? 1 : -1
                            return (winB?.focusHistoryID ?? 0) - (winA?.focusHistoryID ?? 0)
                        })
                    }
                }
                delegate: OverviewWindow {
                    id: window
                    required property var modelData
                    required property int index
                    property int monitorId: windowData?.monitor
                    property var monitor: HyprlandData.monitors.find(m => m.id === monitorId)
                    property var address: `0x${modelData.HyprlandToplevel.address}`
                    windowData: windowByAddress[address]
                    toplevel: modelData
                    monitorData: monitor
                    overviewHeld: root.panelWindow.overviewHeld
               
                    property real sourceMonitorWidth: (monitor?.transform % 2 === 1) ?
                        (monitor?.height ?? 1920) / (monitor?.scale ?? 1) - (monitor?.reserved?.[0] ?? 0) - (monitor?.reserved?.[2] ?? 0) :
                        (monitor?.width ?? 1920) / (monitor?.scale ?? 1) - (monitor?.reserved?.[0] ?? 0) - (monitor?.reserved?.[2] ?? 0)
                    property real sourceMonitorHeight: (monitor?.transform % 2 === 1) ?
                        (monitor?.width ?? 1080) / (monitor?.scale ?? 1) - (monitor?.reserved?.[1] ?? 0) - (monitor?.reserved?.[3] ?? 0) :
                        (monitor?.height ?? 1080) / (monitor?.scale ?? 1) - (monitor?.reserved?.[1] ?? 0) - (monitor?.reserved?.[3] ?? 0)
                    
                    scale: Math.min(root.workspaceImplicitWidth / sourceMonitorWidth, root.workspaceImplicitHeight / sourceMonitorHeight)
                    availableWorkspaceWidth: root.workspaceImplicitWidth
                    availableWorkspaceHeight: root.workspaceImplicitHeight
                    widgetMonitorId: root.monitor.id

                    property bool atInitPosition: (initX == x && initY == y)
                    property int workspaceColIndex: (windowData?.workspace.id - 1) % (Config?.options.overview.columns ?? 3)
                    property int workspaceRowIndex: Math.floor((windowData?.workspace.id - 1) % root.workspacesShown / (Config?.options.overview.columns ?? 3))
                    xOffset: (root.workspaceImplicitWidth + workspaceSpacing) * workspaceColIndex
                    yOffset: (root.workspaceImplicitHeight + workspaceSpacing) * workspaceRowIndex

                    Timer {
                        id: updateWindowPosition
                        interval: Config?.options.hacks.arbitraryRaceConditionDelay ?? 50
                        repeat: false
                        onTriggered: {
                            window.x = Math.round(Math.max((windowData?.at[0] - (monitor?.x ?? 0) - (monitorData?.reserved?.[0] ?? 0)) * root.scale, 0) + xOffset)
                            window.y = Math.round(Math.max((windowData?.at[1] - (monitor?.y ?? 0) - (monitorData?.reserved?.[1] ?? 0)) * root.scale, 0) + yOffset)
                        }
                    }

                    z: atInitPosition ? (root.windowZ + index) : root.windowDraggingZ
                    Drag.hotSpot.x: targetWindowWidth / 2
                    Drag.hotSpot.y: targetWindowHeight / 2
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: hovered = true
                        onExited: hovered = false
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        drag.target: parent
                        onPressed: (mouse) => {
                            root.draggingFromWorkspace = windowData?.workspace.id
                            window.pressed = true
                            window.Drag.active = true
                            window.Drag.source = window
                            window.Drag.hotSpot.x = mouse.x
                            window.Drag.hotSpot.y = mouse.y
                        }
                        onReleased: {
                            const targetWorkspace = root.draggingTargetWorkspace
                            window.pressed = false
                            window.Drag.active = false
                            root.draggingFromWorkspace = -1
                            if (targetWorkspace !== -1 && targetWorkspace !== windowData?.workspace.id) {
                                Hyprland.dispatch(`movetoworkspacesilent ${targetWorkspace}, address:${window.windowData?.address}`)
                                updateWindowPosition.restart()
                            } else {
                                window.x = window.initX
                                window.y = window.initY
                            }
                        }
                        onClicked: (event) => {
                            if (!windowData) return;
                            if (event.button === Qt.LeftButton) {
                                GlobalStates.overviewOpen = false
                                Hyprland.dispatch(`focuswindow address:${windowData.address}`)
                                event.accepted = true
                            } else if (event.button === Qt.MiddleButton) {
                                Hyprland.dispatch(`closewindow address:${windowData.address}`)
                                event.accepted = true
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: dragArea.containsMouse && !window.Drag.active
                            text: `${windowData?.title ?? "Unknown"}\n[${windowData?.class ?? "unknown"}] ${windowData?.xwayland ? "[XWayland] " : ""}`
                        }
                    }
                }
            }

            Rectangle { // Focused workspace indicator
                id: focusedWorkspaceIndicator
                property int activeWorkspaceInGroup: (monitor?.activeWorkspace?.id ?? 1) - (root.workspaceGroup * root.workspacesShown)
                property int activeWorkspaceRowIndex: Math.floor((activeWorkspaceInGroup - 1) / (Config?.options.overview.columns ?? 3))
                property int activeWorkspaceColIndex: (activeWorkspaceInGroup - 1) % (Config?.options.overview.columns ?? 3)
                x: (root.workspaceImplicitWidth + workspaceSpacing) * activeWorkspaceColIndex
                y: (root.workspaceImplicitHeight + workspaceSpacing) * activeWorkspaceRowIndex
                z: root.windowZ
                width: root.workspaceImplicitWidth
                height: root.workspaceImplicitHeight
                color: "transparent"
                radius: Appearance.rounding.screenRounding * root.scale
                border.width: 0
                border.color: root.activeBorderColor
                Behavior on x { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Behavior on y { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            }
        }
    }
}