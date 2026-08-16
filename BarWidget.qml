import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar slot for Todoist. The panel owns the cache, the sync timer, and the
// CLI; this reads the already-shaped label off it so the count stays live
// whether or not the popup has ever been opened.
BarWidget {
  id: root
  moduleName: "io.github.mdetweil.todoist"

  readonly property string icon: "󰄴"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("io.github.mdetweil.todoist")
    : null

  readonly property string panelLabel: panelLoader.item ? panelLoader.item.label : ""
  readonly property int overdueCount: panelLoader.item ? panelLoader.item.overdueCount : 0
  readonly property bool hasWork: panelLoader.item ? panelLoader.item.hasWork : false
  readonly property bool signedIn: panelLoader.item ? panelLoader.item.signedIn : false

  readonly property string setupIcon: "󰄴"

  readonly property string activeIcon: !signedIn ? setupIcon : icon
  readonly property string activeLabel: !signedIn ? "setup" : panelLabel

  readonly property string barLabelMode: setting("barLabel", "Count")
  readonly property bool iconOnly: barLabelMode === "Icon"
  readonly property string nextTitle: panelLoader.item ? panelLoader.item.nextTitle : ""
  readonly property bool marquee: !vertical && signedIn
    && barLabelMode === "Next" && nextTitle !== ""
  readonly property real marqueeWidth: Style.space(150)

  readonly property string displayText: activeLabel === "" ? activeIcon : activeIcon + "  " + activeLabel
  readonly property var verticalLines: activeLabel === "" ? [activeIcon] : [activeIcon, activeLabel]

  function cycleBarLabel() {
    var next = Model.cycleBarLabel(barLabelMode)
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.barLabel = next

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  function focusedInstance() {
    if (root.bar && typeof root.bar.findPanelWidget === "function") {
      var item = root.bar.findPanelWidget(root.moduleName)
      if (item) return item
    }
    return root
  }

  IpcHandler {
    target: "io.github.mdetweil.todoist"

    function sync(): void { root.broadcast("refresh") }
    function cycleLabel(): void { root.focusedInstance().cycleBarLabel() }
    function open(): void { root.focusedInstance().open() }
    function close(): void { root.focusedInstance().close() }
    function show(): void { root.focusedInstance().open() }
    function hide(): void { root.focusedInstance().close() }
    function toggle(): void { root.focusedInstance().togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (root.vertical || root.marquee || root.iconOnly) ? "" : root.displayText
    fontSize: root.iconOnly ? Style.bar.iconFont : Style.font.body
    fixedWidth: root.iconOnly ? Style.bar.iconSlot : (root.marquee ? root.marqueeWidth + Style.space(30) : -1)
    labelVisible: !root.vertical && !root.iconOnly
    hasVisualContent: root.marquee
      ? true
      : (root.vertical ? root.verticalLines.length > 0 : (root.iconOnly ? root.activeIcon !== "" : text !== ""))
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1

    active: root.overdueCount > 0
    dimmed: !root.signedIn

    tooltipText: root.signedIn
      ? (root.hasWork ? "Todoist — click to review" : "Todoist — all clear")
        + "\nright click for " + Model.barLabelDescription(Model.cycleBarLabel(root.barLabelMode))
      : "Todoist — click to connect"

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (b === Qt.RightButton) root.cycleBarLabel()
      else root.togglePanel()
    }

    OpticalGlyph {
      visible: root.iconOnly && !root.vertical
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas
      text: root.activeIcon
      fontFamily: button.fontFamily
      fontSize: Style.bar.iconFont
      color: button.foreground
    }

    Row {
      visible: root.marquee
      anchors.centerIn: parent
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.activeIcon
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }

      Item {
        id: scrollClip
        width: Math.min(root.marqueeWidth, marqueeText.implicitWidth)
        height: button.height
        clip: true
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: marqueeText
          text: root.nextTitle
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          anchors.verticalCenter: parent.verticalCenter

          readonly property bool needsScroll: implicitWidth > scrollClip.width

          onNeedsScrollChanged: if (!needsScroll) x = 0

          SequentialAnimation on x {
            running: marqueeText.needsScroll && !root.opened
            loops: Animation.Infinite

            PauseAnimation { duration: 2000 }
            NumberAnimation {
              from: 0
              to: Math.min(0, scrollClip.width - marqueeText.implicitWidth)
              duration: Math.max(900, (marqueeText.implicitWidth - scrollClip.width) * 28)
              easing.type: Easing.Linear
            }
            PauseAnimation { duration: 1600 }
            NumberAnimation { to: 0; duration: 400; easing.type: Easing.OutCubic }
          }
        }
      }
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        Text {
          required property var modelData
          width: parent.width
          height: Style.bar.iconSlot
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: modelData
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
        }
      }
    }
  }
}
