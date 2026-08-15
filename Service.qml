import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Everything that must exist once, not once per screen.
//
// A bar surface is created per monitor, so a two-display desktop runs two of
// every panel. Left in the panel, a timer fires twice, a cache is parsed
// twice, and the write queue drains twice.
//
// The shell mounts a `service` plugin exactly once and hands it to views
// through shell.serviceFor(id). This holds the cache, the sync timer, the
// write queue, and the held-action window. Panels render it.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string cli: pluginDir + "bin/omarchy-todoist"
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/todoist"

  // ---- cache -------------------------------------------------------------

  property var cache: Model.parseCache("")
  property date nowDate: new Date()

  readonly property bool signedIn: cache.syncedAt > 0 && !cache.authRequired
  readonly property int queuedCount: cache.queued || 0
  readonly property int todayStamp: Model.dateStamp(nowDate)

  property FileView dataFile: FileView {
    path: root.statePath + "/data.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.cache = Model.parseCache(text())
      root.pendingIds = ({})
      root.pendingAdds = []
    }
    onLoadFailed: root.cache = Model.parseCache("")
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.nowDate = date
  }

  // ---- sync --------------------------------------------------------------

  readonly property int refreshIntervalSec: Model.syncIntervalSeconds(setting("syncInterval", "5 minutes"))
  readonly property bool autoSyncs: refreshIntervalSec > 0
  property string actionError: ""

  readonly property bool syncing: syncProc.running

  function refresh(force) {
    nowDate = new Date()
    if (syncProc.running) return
    syncProc.command = force === false
      ? [root.cli, "sync", "--max-age", String(Math.max(30, refreshIntervalSec - 15))]
      : [root.cli, "sync"]
    syncProc.running = true
  }

  Process {
    id: syncProc
    command: [root.cli, "sync"]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw !== "") root.actionError = Model.elide(raw, 120)
      }
    }
    onExited: function(code) {
      if (code === 0) root.actionError = ""
      root.nowDate = new Date()
    }
  }

  Timer {
    id: syncTimer
    interval: Math.max(60, root.refreshIntervalSec) * 1000
    repeat: true
    running: root.autoSyncs
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  Timer {
    interval: 1500
    running: !root.autoSyncs
    repeat: false
    onTriggered: root.refresh(false)
  }

  // ---- writes ------------------------------------------------------------

  property var actionQueue: []

  Process {
    id: actionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw !== "") root.actionError = Model.elide(raw, 120)
      }
    }
    onExited: function(code) {
      if (code === 0) root.actionError = ""
      root.connecting = false
      root.drainQueue()
    }
  }

  function runAction(args) {
    if (actionProc.running) {
      var queued = actionQueue.slice()
      queued.push(args)
      actionQueue = queued
      return
    }
    actionProc.command = [root.cli].concat(args)
    actionProc.running = true
  }

  function drainQueue() {
    if (actionQueue.length === 0) return
    var queued = actionQueue.slice()
    var next = queued.shift()
    actionQueue = queued
    actionProc.command = [root.cli].concat(next)
    actionProc.running = true
  }

  // ---- held actions ------------------------------------------------------

  property var pendingIds: ({})
  property var pendingAdds: []

  readonly property int undoSeconds: Math.max(0, parseInt(setting("undoSeconds", 6), 10) || 0)

  property var pendingActions: []
  property int undoTick: 0

  readonly property var pendingAction: Model.topPending(pendingActions)
  readonly property int pendingCount: pendingActions.length
  readonly property int undoLeft: pendingAction
    ? Model.undoSecondsLeft(pendingAction.deadline, Date.now() + undoTick * 0)
    : 0

  function scheduleAction(kind, title, args, key) {
    if (undoSeconds <= 0) {
      runAction(args)
      return
    }
    pendingActions = pendingActions.concat([{
      kind: kind,
      title: title,
      args: args,
      key: key,
      deadline: Date.now() + undoSeconds * 1000
    }])
  }

  function flushExpired() {
    var split = Model.expirePending(pendingActions, Date.now())
    if (split.due.length === 0) return
    pendingActions = split.remaining
    for (var i = 0; i < split.due.length; i++) runAction(split.due[i].args)
  }

  function flushPending() {
    if (pendingActions.length === 0) return
    var held = pendingActions
    pendingActions = []
    for (var i = 0; i < held.length; i++) runAction(held[i].args)
  }

  function cancelPending() {
    var action = Model.topPending(pendingActions)
    if (!action) return
    pendingActions = Model.dropTopPending(pendingActions)
    clearPendingTask(action.key)
  }

  function clearPendingTask(taskId) {
    var next = {}
    for (var key in pendingIds) if (key !== taskId) next[key] = pendingIds[key]
    pendingIds = next
  }

  function markPending(taskId) {
    var next = {}
    for (var key in pendingIds) next[key] = pendingIds[key]
    next[taskId] = true
    pendingIds = next
  }

  function completeTask(task) {
    if (!task || !task.id) return
    markPending(task.id)
    scheduleAction("complete", task.title, ["complete", String(task.id)], String(task.id))
  }

  function submitEdit(taskId, text) {
    var args = Model.editArgs(taskId, text)
    if (!args) return false
    runAction(args)
    return true
  }

  function submitQuickAdd(text) {
    var args = Model.quickAddArgs(text)
    if (!args) return null
    pendingAdds = pendingAdds.concat([{ id: "", title: args[1], ghost: true }])
    runAction(args)
    return Model.parseQuickAdd(text)
  }

  Timer {
    id: undoTicker
    interval: 250
    repeat: true
    running: root.pendingActions.length > 0
    onTriggered: {
      root.undoTick++
      root.flushExpired()
    }
  }

  // ---- connecting --------------------------------------------------------

  property bool connecting: false

  property FileView tokenFile: FileView {
    path: root.statePath + "/token-paste"
    atomicWrites: true
    printErrors: false
  }

  function connectWithToken(token) {
    var trimmed = String(token || "").trim()
    if (trimmed === "") return
    connecting = true
    actionError = ""
    tokenFile.setText(trimmed + "\n")
    runAction(["login", "--token", trimmed])
  }
}
