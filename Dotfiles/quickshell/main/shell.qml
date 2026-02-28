import "./main"

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import QtQuick

ShellRoot {
    Bar {
        id: bar
    }

    NotificationServer {
        id: notificationServer
        bodySupported: true
        actionsSupported: true
        imageSupported: true
    }

    WidgetPanel {
        id: wp
    }

    NotificationToastWindow {
        notifServer: notificationServer
    }

    Launcher {
        id: launcher
    }

    WallpaperChanger {
        id: wallpaperChanger
    }

    ControlCenter {
        id: controlCenter
    }
}