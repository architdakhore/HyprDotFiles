pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root
    property bool launcherOpen: false
    property bool wallpaperOpen: false
    property bool controlCenterOpen: false
}