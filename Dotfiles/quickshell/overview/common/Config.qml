pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root
    
    property QtObject options: QtObject {
        property QtObject appearance: QtObject {
            property bool useMatugenColors: false
        }

        property QtObject overview: QtObject {
            property int rows: 1
            property int columns: 5
            property real scale: 0.195
            property bool enable: true
            property bool hideEmptyRows: true 
        }
        
        property QtObject hacks: QtObject {
            property int arbitraryRaceConditionDelay: 150
        }
    }
}
