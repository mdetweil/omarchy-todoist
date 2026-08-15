import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Todoist popup: tasks due now, quick-add, and inline editing.
//
// The panel never talks to Todoist itself. `bin/omarchy-todoist` owns the
// token and every request; this reads the JSON cache that CLI writes and
// shells back out for writes.
Panel {
  id: root
  moduleName: "io.github.mdetweil.todoist"
  ipcTarget: "io.github.mdetweil.todoist"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string cli: pluginDir + "bin/omarchy-todoist"

  // ---- the shared service ------------------------------------------------

  readonly property var svc: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("io.github.mdetweil.todoist")
    : null

  onSvcChanged: pushSettings()
  onSettingsChanged: pushSettings()
  function pushSettings() {
    if (svc && "settings" in svc) svc.settings = root.settings
  }

  // ---- cache (read through the service) ----------------------------------

  readonly property var cache: svc ? svc.cache : Model.parseCache("")
  readonly property date nowDate: svc ? svc.nowDate : new Date()

  readonly property bool signedIn: cache.syncedAt > 0 && !cache.authRequired
  readonly property string cacheError: cache.error ? String(cache.error) : ""
  readonly property int queuedCount: cache.queued || 0

  readonly property int staleMinutes: Model.staleMinutes(cache.syncedAt, nowDate.getTime())

  readonly property int todayStamp: Model.dateStamp(nowDate)

  readonly property bool showTasks: setting("showTasks", true) !== false
  readonly property string horizon: setting("horizon", "Today")
  property string viewHorizon: horizon
  onHorizonChanged: viewHorizon = horizon

  function cycleView(delta) {
    viewHorizon = Model.cycleHorizon(viewHorizon, delta)
  }

  readonly property string nextView: Model.cycleHorizon(viewHorizon, 1)
  readonly property string viewSwitchHint: (nextView === "Today" ? "Back to " : "Show ") + nextView
  readonly property bool includeOverdue: setting("includeOverdue", true) !== false
  readonly property int maxTasks: Math.max(3, parseInt(setting("maxTasks", 12), 10) || 12)

  readonly property var pendingIds: svc ? svc.pendingIds : ({})
  readonly property var pendingAdds: svc ? svc.pendingAdds : []
  readonly property var pendingAction: svc ? svc.pendingAction : null
  readonly property int pendingCount: svc ? svc.pendingCount : 0
  readonly property int undoLeft: svc ? svc.undoLeft : 0
  readonly property int undoSeconds: svc ? svc.undoSeconds : 6
  readonly property string actionError: svc ? svc.actionError : ""
  readonly property bool connecting: svc ? svc.connecting : false
  readonly property int refreshIntervalSec: svc ? svc.refreshIntervalSec : 300

  readonly property bool syncing: svc ? svc.syncing === true : false

  function refresh(force) { if (svc) svc.refresh(force) }
  function runAction(args) { if (svc) svc.runAction(args) }
  function completeTask(task) { if (svc) svc.completeTask(task) }
  function cancelPending() { if (svc) svc.cancelPending() }
  function flushPending() { if (svc) svc.flushPending() }

  function connectWithToken() {
    if (!svc) return
    svc.connectWithToken(tokenPaste.text)
    tokenPaste.text = ""
  }

  property string editingTaskId: ""

  function beginEdit() {
    if (cursor < 0 || cursor >= navRows.length) return
    var row = navRows[cursor]
    if (row.section !== "task") return
    var task = displayTasks[row.index]
    if (!task || !task.id) return
    editingTaskId = String(task.id)
    quickAdd.text = Model.editLineFor(task)
    quickAdd.forceActiveFocus()
    quickAdd.selectAll()
  }

  function cancelEdit() {
    editingTaskId = ""
    quickAdd.text = ""
    keyCatcher.forceActiveFocus()
  }

  function submitQuickAdd() {
    if (!svc) return
    var text = String(quickAdd.text || "").trim()
    if (text === "") return

    if (editingTaskId !== "") {
      var id = editingTaskId
      editingTaskId = ""
      quickAdd.text = ""
      svc.submitEdit(id, text)
      return
    }

    quickAdd.text = ""
    var parsed = svc.submitQuickAdd(text)
    if (parsed)
      viewHorizon = Model.widerHorizon(viewHorizon, Model.horizonForDue(parsed.due, nowDate))
  }

  readonly property var allDueTasks: showTasks
    ? Model.dueTasks(cache.tasks, { now: nowDate, horizon: viewHorizon, includeOverdue: includeOverdue })
    : []
  readonly property var visibleTasks: filterPending(allDueTasks)
  readonly property var listedTasks: visibleTasks.slice(0, maxTasks)

  readonly property var displayTasks: pendingAdds.concat(listedTasks)
  readonly property int hiddenTaskCount: Math.max(0, visibleTasks.length - listedTasks.length)
  readonly property int overdueCount: Model.overdueCount(visibleTasks, nowDate)

  readonly property var tagsById: Model.tagIndex(cache.tags)

  property bool cursorActive: false
  property int cursor: -1
  property bool helpVisible: false

  readonly property var navRows: {
    var rows = []
    if (showTasks) {
      for (var i = 0; i < displayTasks.length; i++) rows.push({ section: "task", index: i })
    }
    return rows
  }

  function cursorToFirst() {
    cursorActive = true
    cursor = navRows.length > 0 ? 0 : -1
  }

  function cursorToLast() {
    cursorActive = true
    cursor = navRows.length - 1
  }

  function moveCursor(delta) {
    cursorActive = true
    var count = navRows.length
    if (count === 0) { cursor = -1; return }
    if (cursor < 0) cursor = delta > 0 ? 0 : count - 1
    else cursor = Math.max(0, Math.min(count - 1, cursor + delta))
  }

  function syncCursorTo(section, index) {
    for (var i = 0; i < navRows.length; i++) {
      if (navRows[i].section === section && navRows[i].index === index) { cursor = i; return }
    }
  }

  function activateCursor() {
    if (cursor < 0 || cursor >= navRows.length) return
    var row = navRows[cursor]
    if (row.section === "task") completeTask(displayTasks[row.index])
  }

  function isCursorOn(section, index) {
    if (!cursorActive || cursor < 0 || cursor >= navRows.length) return false
    var row = navRows[cursor]
    return row.section === section && row.index === index
  }

  onNavRowsChanged: if (cursor >= navRows.length) cursor = navRows.length - 1

  readonly property string nextTitle: Model.nextTaskTitle(visibleTasks)
  readonly property string label: Model.barLabel(setting("barLabel", "Count"), visibleTasks, nowDate)
  readonly property bool hasWork: visibleTasks.length > 0

  function filterPending(tasks) {
    var result = []
    for (var i = 0; i < tasks.length; i++) {
      if (!pendingIds[tasks[i].id]) result.push(tasks[i])
    }
    return result
  }

  // ---- lifecycle --------------------------------------------------------

  function open() {
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    root.controller.show()
    root.refresh()
  }

  function close() {
    flushPending()
    viewHorizon = horizon
    cursor = -1
    cursorActive = false
    editingTaskId = ""
    quickAdd.text = ""
    quickAdd.focus = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // ---- surface ----------------------------------------------------------

  readonly property color fg: Color.popups.text
  readonly property color muted: Qt.darker(fg, 1.5)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: quickAdd.activeFocus
      onCloseRequested: {
        if (root.helpVisible) root.helpVisible = false
        else if (root.pendingAction) root.cancelPending()
        else root.close()
      }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy > 0 ? 1 : -1)
      }
      onActivateRequested: root.activateCursor()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "?") root.helpVisible = !root.helpVisible
        else if (text === "r") root.refresh()
        else if (text === "a") quickAdd.forceActiveFocus()
        else if (text === "e") root.beginEdit()
        else if (text === "u") root.cancelPending()
        else if (text === "v") root.cycleView(1)
        else if (text === "V") root.cycleView(-1)
        else if (text === "g") root.cursorToFirst()
        else if (text === "G") root.cursorToLast()
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: scroll.width
          spacing: Style.space(8)

          // ---- header
          Item {
            width: parent.width
            height: Math.max(headerText.implicitHeight, syncButton.height)

            Column {
              id: headerText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Item {
                implicitWidth: viewRow.implicitWidth
                implicitHeight: viewRow.implicitHeight
                width: implicitWidth
                height: implicitHeight

                Row {
                  id: viewRow
                  spacing: Style.space(5)

                  Text {
                    id: viewLabel
                    text: root.visibleTasks.length === 0
                      ? "All clear"
                      : root.viewHorizon
                    color: viewSwitch.containsMouse ? Color.accent : root.fg
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Row {
                    anchors.verticalCenter: viewLabel.verticalCenter
                    spacing: Style.space(3)

                    Repeater {
                      model: Model.horizons()

                      Text {
                        required property int index
                        readonly property bool current: index === Model.horizonIndex(root.viewHorizon)

                        text: current ? "●" : "○"
                        color: current
                          ? (viewSwitch.containsMouse ? Color.accent : root.fg)
                          : root.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }

                MouseArea {
                  id: viewSwitch
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.cycleView(1)

                  PanelToolTip {
                    text: root.viewSwitchHint + "  (v)"
                    visible: viewSwitch.containsMouse
                  }
                }
              }

              Text {
                text: root.headerSubtitle()
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              anchors.right: helpButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              visible: root.queuedCount > 0
              text: " " + root.queuedCount
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption

              PanelToolTip {
                text: root.queuedCount + " change(s) waiting for Todoist"
                visible: queuedHover.containsMouse
              }

              MouseArea {
                id: queuedHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
              }
            }

            PanelActionButton {
              id: helpButton
              anchors.right: syncButton.left
              anchors.rightMargin: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              iconText: ""
              tooltipText: "Keyboard shortcuts  (?)"
              foreground: root.helpVisible ? Color.accent : root.muted
              onClicked: root.helpVisible = !root.helpVisible
            }

            PanelActionButton {
              id: syncButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.syncing ? "" : ""
              tooltipText: root.syncing ? "Syncing…" : "Sync now"
              foreground: root.fg
              onClicked: root.refresh()
            }
          }

          // ---- keyboard help
          Column {
            width: parent.width
            spacing: Style.space(3)
            visible: root.helpVisible

            PanelSeparator { width: parent.width; foreground: root.fg }

            PanelSectionHeader { text: "KEYS"; foreground: root.fg }

            Repeater {
              model: [
                { key: "↑ ↓", what: "move between tasks" },
                { key: "enter", what: "complete the task" },
                { key: "u", what: "undo the held action" },
                { key: "a", what: "add a task" },
                { key: "e", what: "edit the selected task" },
                { key: "#label", what: "attach a Todoist label" },
                { key: "!1 !2 !3", what: "priority: high, medium, low" },
                { key: "tomorrow", what: "trailing date word sets due date" },
                { key: "r", what: "sync now" },
                { key: "g / G", what: "first / last row" },
                { key: "v", what: "cycle range: today → tomorrow → 7 days ↺" },
                { key: "tab", what: "next bar panel" },
                { key: "?", what: "show or hide this list" },
                { key: "esc", what: "back out, then close" }
              ]

              Row {
                required property var modelData
                width: content.width
                spacing: Style.space(8)

                Text {
                  width: Style.space(52)
                  horizontalAlignment: Text.AlignRight
                  text: modelData.key
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  text: modelData.what
                  color: root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // ---- undo window
          Rectangle {
            width: parent.width
            height: root.pendingAction ? Style.space(28) : 0
            visible: root.pendingAction !== null
            radius: Style.space(4)
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(30)
                  - undoCount.implicitWidth - undoDepth.implicitWidth
                elide: Text.ElideRight
                text: Model.undoLabel(root.pendingAction, root.undoLeft)
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                id: undoDepth
                anchors.verticalCenter: parent.verticalCenter
                text: Model.heldSuffix(root.pendingCount)
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                id: undoCount
                anchors.verticalCenter: parent.verticalCenter
                text: "undo " + root.undoLeft + "s"
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.cancelPending()
            }
          }

          // ---- setup card (not signed in)
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: !root.signedIn

            PanelSeparator { width: parent.width; foreground: root.fg }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.cache.authRequired
                ? "Todoist rejected this token. Paste a fresh one to reconnect."
                : "Connect your Todoist account."
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "1. Open todoist.com/app/settings/integrations\n"
                + "2. Find 'API token' and copy it\n"
                + "3. Paste below and press Connect"
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              lineHeight: 1.35
            }

            TextField {
              id: tokenPaste
              width: parent.width
              password: true
              placeholderText: "Paste API token…"
              foreground: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              enabled: !root.connecting
              onAccepted: root.connectWithToken()
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Button {
                text: root.connecting ? "Connecting…" : "Connect"
                enabled: !root.connecting && String(tokenPaste.text || "").trim() !== ""
                onClicked: root.connectWithToken()
              }

              Button {
                text: "Open Todoist"
                onClicked: if (root.bar) root.bar.run("xdg-open https://app.todoist.com")
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              visible: !root.cache.authRequired
              text: " The token stays on this machine, in a 0600 file."
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          // ---- quick add
          TextField {
            id: quickAdd
            width: parent.width
            visible: root.signedIn && root.showTasks
            placeholderText: root.editingTaskId !== ""
              ? "Editing — enter to save, esc to cancel"
              : "Add a task…  #label  !1  tomorrow"
            foreground: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            onAccepted: root.submitQuickAdd()
            Keys.onEscapePressed: root.cancelEdit()
          }

          // ---- tasks
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.signedIn && root.showTasks

            PanelSeparator { width: parent.width; foreground: root.fg }

            Item {
              width: parent.width
              height: sectionLabel_tasks.implicitHeight

              PanelSectionHeader {
                id: sectionLabel_tasks
                anchors.left: parent.left
                text: "TASKS"
                foreground: root.fg
              }

              PanelSectionHeader {
                anchors.right: parent.right
                anchors.baseline: sectionLabel_tasks.baseline
                text: root.overdueCount > 0
                  ? root.overdueCount + " LATE"
                  : String(root.visibleTasks.length)
                foreground: root.overdueCount > 0 ? Color.accent : root.muted
              }
            }

            Text {
              width: parent.width
              visible: root.displayTasks.length === 0
              text: "Nothing due."
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.displayTasks

              Rectangle {
                id: taskRow
                required property var modelData
                required property int index
                readonly property bool selected: root.isCursorOn("task", index)
                readonly property bool pending: modelData.ghost === true
                readonly property bool late: !pending && Model.isOverdue(modelData, root.nowDate)
                readonly property string tier: Model.dueTier(modelData, root.nowDate)
                readonly property string tagHex: Model.tagColor(modelData, root.tagsById)
                readonly property string tagName: Model.tagLabel(modelData, root.tagsById)

                width: content.width
                height: Style.space(26)
                radius: Style.space(4)
                color: (taskHover.containsMouse || taskRow.selected)
                  ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                  : "transparent"
                border.width: taskRow.selected ? 1 : 0
                border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.55)

                MouseArea {
                  id: taskHover
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton
                  onContainsMouseChanged: if (containsMouse) {
                    root.cursorActive = false
                    root.syncCursorTo("task", taskRow.index)
                  }
                }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(8)

                  Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(18)
                    height: Style.space(18)

                    Text {
                      anchors.centerIn: parent
                      opacity: taskRow.pending ? 0.45 : 1
                      text: circleHover.containsMouse ? "" : ""
                      color: taskRow.late ? Color.accent : root.muted
                      font.family: Style.font.family
                      font.pixelSize: Style.font.icon
                    }

                    MouseArea {
                      id: circleHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.completeTask(taskRow.modelData)
                    }
                  }

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: taskRow.tagHex === "" ? 0 : 1
                    width: Style.space(6)
                    height: Style.space(6)
                    radius: width / 2
                    color: taskRow.tagHex === "" ? "transparent" : taskRow.tagHex

                    PanelToolTip {
                      text: taskRow.tagName
                      visible: tagHover.containsMouse && taskRow.tagName !== ""
                    }

                    MouseArea {
                      id: tagHover
                      anchors.fill: parent
                      hoverEnabled: true
                    }
                  }

                  Item {
                    id: titleClip
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(30)
                      - Style.space(14)
                      - dueLabel.implicitWidth
                    height: taskRow.height
                    clip: true

                    Text {
                      id: titleText
                      anchors.verticalCenter: parent.verticalCenter
                      text: String(taskRow.modelData.title || "")
                      color: taskRow.tier === "upcoming" ? root.muted : root.fg
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      font.bold: Model.priorityRank(taskRow.modelData) === "high"

                      readonly property bool overflowing: implicitWidth > titleClip.width
                      readonly property bool scrolling: overflowing
                        && (taskRow.selected || taskHover.containsMouse)

                      width: scrolling ? implicitWidth : titleClip.width
                      elide: scrolling ? Text.ElideNone : Text.ElideRight

                      onScrollingChanged: if (!scrolling) x = 0

                      SequentialAnimation on x {
                        running: titleText.scrolling
                        loops: Animation.Infinite

                        PauseAnimation { duration: 700 }
                        NumberAnimation {
                          from: 0
                          to: Math.min(0, titleClip.width - titleText.implicitWidth)
                          duration: Math.max(900, (titleText.implicitWidth - titleClip.width) * 28)
                          easing.type: Easing.Linear
                        }
                        PauseAnimation { duration: 1100 }
                        NumberAnimation { to: 0; duration: 350; easing.type: Easing.OutCubic }
                      }
                    }
                  }

                  Text {
                    id: dueLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: taskRow.pending ? "adding…" : Model.dueLabel(taskRow.modelData, root.nowDate)
                    color: taskRow.tier === "overdue"
                      ? Color.accent
                      : (taskRow.tier === "today" ? root.fg : root.muted)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            Text {
              width: parent.width
              visible: root.hiddenTaskCount > 0
              text: "+" + root.hiddenTaskCount + " more"
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          // ---- link out to Todoist
          Item {
            width: parent.width
            height: Style.space(22)
            visible: root.signedIn

            Row {
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                id: escapeLabel
                text: "Open in Todoist"
                color: escapeHover.containsMouse ? Color.accent : root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.verticalCenter: escapeLabel.verticalCenter
                text: ""
                color: escapeHover.containsMouse ? Color.accent : root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: escapeHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.bar) root.bar.run("xdg-open https://app.todoist.com")
                root.close()
              }
            }
          }

          // ---- footer
          Text {
            width: parent.width
            visible: root.actionError !== "" || (root.cacheError !== "" && root.signedIn)
            wrapMode: Text.WordWrap
            text: root.actionError !== "" ? root.actionError : root.cacheError
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  function headerSubtitle() {
    if (!signedIn) return "Not connected"
    if (root.syncing) return "Syncing…"

    var parts = []
    if (showTasks) parts.push(visibleTasks.length + (visibleTasks.length === 1 ? " task" : " tasks"))
    if (queuedCount > 0) parts.push(queuedCount + " waiting to send")

    var age = staleMinutes
    if (age > 10) parts.push("synced " + age + "m ago")
    return parts.join(" · ")
  }
}
