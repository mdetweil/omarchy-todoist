// Pure data shaping for the Todoist widget. No QML types in here on
// purpose: everything below is plain JS so it can be exercised by node in
// tests/ without a running shell (see tests/model.test.js).

var STATUS_TODO = 0
var STATUS_DONE = 2

// ---- dates -------------------------------------------------------------

function parseApiDate(value) {
  if (!value) return null
  var text = String(value).trim()
  if (text === "") return null
  // Todoist all-day format: "YYYY-MM-DD"
  // Todoist timed format: "YYYY-MM-DDTHH:MM:SS[Z|+HH:MM]"
  var parsed = new Date(text.length === 10 ? text + "T00:00:00" : text)
  return isNaN(parsed.getTime()) ? null : parsed
}

function taskDueDate(task) {
  if (!task || !task.dueDate) return null
  if (task.isAllDay) {
    var head = String(task.dueDate).slice(0, 10).split("-")
    if (head.length === 3) {
      var day = new Date(Number(head[0]), Number(head[1]) - 1, Number(head[2]))
      return isNaN(day.getTime()) ? null : day
    }
  }
  return parseApiDate(task.dueDate)
}

function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

function endOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 999)
}

function addDays(date, days) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
}

function dateStamp(date) {
  var month = date.getMonth() + 1
  var day = date.getDate()
  return date.getFullYear() * 10000 + month * 100 + day
}

function stampToDate(stamp) {
  var text = String(stamp)
  if (text.length !== 8) return null
  return new Date(Number(text.slice(0, 4)), Number(text.slice(4, 6)) - 1, Number(text.slice(6, 8)))
}

// ---- tasks -------------------------------------------------------------

var HORIZONS = ["Today", "Tomorrow", "Next 7 days"]

function horizons() {
  return HORIZONS
}

function horizonIndex(horizon) {
  var i = HORIZONS.indexOf(String(horizon))
  return i < 0 ? 0 : i
}

function cycleHorizon(current, delta) {
  var i = HORIZONS.indexOf(String(current))
  if (i < 0) i = 0
  var next = i + (delta || 1)
  if (next >= HORIZONS.length) next = 0
  if (next < 0) next = HORIZONS.length - 1
  return HORIZONS[next]
}

function horizonForDue(dueWord, now) {
  var word = String(dueWord || "today").toLowerCase()
  if (word === "today" || word === "yesterday") return "Today"
  if (word === "tomorrow") return "Tomorrow"

  var parts = word.split("-")
  if (parts.length === 3) {
    var target = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    if (!isNaN(target.getTime())) {
      var days = Math.round((startOfDay(target).getTime() - startOfDay(now || new Date()).getTime()) / 86400000)
      if (days <= 0) return "Today"
      if (days === 1) return "Tomorrow"
      return "Next 7 days"
    }
  }
  return "Today"
}

function widerHorizon(a, b) {
  return HORIZONS.indexOf(a) >= HORIZONS.indexOf(b) ? a : b
}

function horizonDays(horizon) {
  if (horizon === "Tomorrow") return 1
  if (horizon === "Next 7 days") return 7
  return 0
}

function isOpen(task) {
  return task && task.status !== STATUS_DONE && !task.deleted
}

function isOverdue(task, now) {
  var due = taskDueDate(task)
  if (!due) return false
  if (task.isAllDay) return dateStamp(due) < dateStamp(now)
  return due.getTime() < now.getTime()
}

function dueTasks(tasks, options) {
  var opts = options || {}
  var now = opts.now || new Date()
  var includeOverdue = opts.includeOverdue !== false
  var cutoff = endOfDay(addDays(now, horizonDays(opts.horizon))).getTime()

  var result = []
  for (var i = 0; i < (tasks || []).length; i++) {
    var task = tasks[i]
    if (!isOpen(task)) continue

    var due = taskDueDate(task)
    if (!due) continue

    var late = isOverdue(task, now)
    if (late && !includeOverdue) continue

    var dueValue = task.isAllDay ? endOfDay(due).getTime() : due.getTime()
    if (!late && dueValue > cutoff) continue

    result.push(task)
  }

  result.sort(function(a, b) {
    var aLate = isOverdue(a, now) ? 0 : 1
    var bLate = isOverdue(b, now) ? 0 : 1
    if (aLate !== bLate) return aLate - bLate

    var aDue = taskDueDate(a)
    var bDue = taskDueDate(b)
    var aTime = aDue ? aDue.getTime() : 0
    var bTime = bDue ? bDue.getTime() : 0
    if (aTime !== bTime) return aTime - bTime

    var aPriority = Number(a.priority || 0)
    var bPriority = Number(b.priority || 0)
    if (aPriority !== bPriority) return bPriority - aPriority
    return Number(a.sortOrder || 0) - Number(b.sortOrder || 0)
  })

  return result
}

function nextTaskTitle(tasks) {
  var next = nextTask(tasks)
  return next ? String(next.title || "") : ""
}

function nextTask(tasks) {
  return (tasks && tasks.length > 0) ? tasks[0] : null
}

function dueLabel(task, now) {
  var due = taskDueDate(task)
  if (!due) return ""
  var reference = now || new Date()
  var dayDelta = Math.round((startOfDay(due).getTime() - startOfDay(reference).getTime()) / 86400000)

  if (task.isAllDay) {
    if (dayDelta === 0) return "Today"
    if (dayDelta === 1) return "Tomorrow"
    if (dayDelta === -1) return "Yesterday"
    if (dayDelta < 0) return Math.abs(dayDelta) + "d late"
    return dayDelta + "d"
  }

  var clock = pad2(due.getHours()) + ":" + pad2(due.getMinutes())
  if (dayDelta === 0) return clock
  if (dayDelta === 1) return "Tmw " + clock
  if (dayDelta === -1) return "Yst " + clock
  if (dayDelta < 0) return Math.abs(dayDelta) + "d late"
  return dayDelta + "d " + clock
}

function pad2(value) {
  return value < 10 ? "0" + value : String(value)
}

// Display priority scale: 0 none, 1 low, 3 medium, 5 high.
// (Matches the TickTick convention used in Model.js so QML does not change.)
function priorityRank(task) {
  var value = Number((task && task.priority) || 0)
  if (value >= 5) return "high"
  if (value >= 3) return "medium"
  if (value >= 1) return "low"
  return "none"
}

function projectName(projects, projectId, inboxId) {
  if (projectId && projectId === inboxId) return "Inbox"
  for (var i = 0; i < (projects || []).length; i++) {
    if (projects[i].id === projectId) return projects[i].name || ""
  }
  return ""
}

// ---- labels (Todoist's equivalent of tags) -----------------------------

// Tasks reference labels by their lowercase name; color lives on the label
// object. Todoist labels use the same `name` key as TickTick tags, so
// the tag* helpers below work unchanged.
function tagIndex(tags) {
  var index = {}
  for (var i = 0; i < (tags || []).length; i++) {
    var tag = tags[i]
    if (tag && tag.name) index[String(tag.name)] = tag
  }
  return index
}

function firstTag(task, index) {
  var names = (task && task.tags) || []
  for (var i = 0; i < names.length; i++) {
    var tag = index[String(names[i])]
    if (tag) return tag
  }
  return null
}

function tagColor(task, index) {
  var tag = firstTag(task, index)
  return tag && tag.color ? String(tag.color) : ""
}

function tagLabel(task, index) {
  var tag = firstTag(task, index)
  return tag ? String(tag.label || tag.name || "") : ""
}

// ---- sync interval -----------------------------------------------------

var SYNC_INTERVALS = {
  "2 minutes": 120,
  "5 minutes": 300,
  "15 minutes": 900,
  "1 hour": 3600,
  "Only when opened": 0
}

function syncIntervalSeconds(label) {
  var seconds = SYNC_INTERVALS[String(label)]
  return seconds === undefined ? 300 : seconds
}

function syncIntervalLabels() {
  return ["2 minutes", "5 minutes", "15 minutes", "1 hour", "Only when opened"]
}

// ---- quick add ---------------------------------------------------------

// #label syntax matches Todoist's own convention.
// !priority is the same extension from the TickTick plugin.
var PRIORITY_WORDS = {
  "1": 5, "high": 5, "h": 5,
  "2": 3, "medium": 3, "med": 3, "m": 3,
  "3": 1, "low": 1, "l": 1,
  "0": 0, "none": 0
}

function parseQuickAdd(text) {
  var rest = String(text || "")
  var tags = []
  var priority = 0
  var due = "today"
  var dueGiven = false

  rest = rest.replace(/(^|\s)#([^\s#]+)/g, function(match, lead, tag) {
    tags.push(String(tag).toLowerCase())
    return lead
  })

  rest = rest.replace(/(^|\s)!([A-Za-z0-9]+)/g, function(match, lead, word) {
    var mapped = PRIORITY_WORDS[String(word).toLowerCase()]
    if (mapped === undefined) return match
    priority = mapped
    return lead
  })

  var dateMatch = rest.match(/\s(?:for\s+|on\s+|due\s+|by\s+)?(today|tomorrow|yesterday|\d{4}-\d{2}-\d{2})\s*$/i)
  if (dateMatch) {
    due = dateMatch[1].toLowerCase()
    dueGiven = true
    rest = rest.slice(0, dateMatch.index)
  }

  return {
    title: rest.replace(/\s+/g, " ").trim(),
    tags: tags,
    priority: priority,
    due: due,
    dueGiven: dueGiven
  }
}

function editLineFor(task, index) {
  if (!task) return ""
  var parts = [String(task.title || "")]

  var names = (task.tags || [])
  for (var i = 0; i < names.length; i++) parts.push("#" + String(names[i]))

  var rank = priorityRank(task)
  if (rank === "high") parts.push("!1")
  else if (rank === "medium") parts.push("!2")
  else if (rank === "low") parts.push("!3")

  var due = taskDueDate(task)
  if (due) {
    var delta = Math.round((startOfDay(due).getTime() - startOfDay(new Date()).getTime()) / 86400000)
    if (delta === 0) parts.push("today")
    else if (delta === 1) parts.push("tomorrow")
    else if (delta === -1) parts.push("yesterday")
    else parts.push(due.getFullYear() + "-" + pad2(due.getMonth() + 1) + "-" + pad2(due.getDate()))
  }

  return parts.join(" ")
}

function editArgs(taskId, text) {
  var parsed = parseQuickAdd(text)
  if (parsed.title === "") return null
  var args = [
    "update", String(taskId),
    "--title", parsed.title,
    "--priority", String(parsed.priority),
    "--tags", parsed.tags.join(",")
  ]
  if (parsed.dueGiven) args = args.concat(["--due", parsed.due])
  return args
}

function quickAddArgs(text) {
  var parsed = parseQuickAdd(text)
  if (parsed.title === "") return null
  var args = ["add", parsed.title, "--due", parsed.due]
  if (parsed.priority > 0) args = args.concat(["--priority", String(parsed.priority)])
  if (parsed.tags.length > 0) args = args.concat(["--tags", parsed.tags.join(",")])
  return args
}

// ---- due tiers ---------------------------------------------------------

function dueTier(task, now) {
  if (isOverdue(task, now)) return "overdue"
  var due = taskDueDate(task)
  if (!due) return "upcoming"
  return dateStamp(due) === dateStamp(now || new Date()) ? "today" : "upcoming"
}

// ---- bar label ---------------------------------------------------------

var BAR_LABEL_MODES = ["Count", "Next", "Icon"]

function cycleBarLabel(current) {
  var i = BAR_LABEL_MODES.indexOf(String(current))
  if (i < 0) i = 0
  return BAR_LABEL_MODES[(i + 1) % BAR_LABEL_MODES.length]
}

function barLabelDescription(mode) {
  if (mode === "Next") return "next task"
  if (mode === "Icon") return "icon only"
  return "counts"
}

function barLabel(mode, tasks, now) {
  if (mode === "Icon") return ""

  if (mode === "Next") {
    var next = nextTask(tasks)
    return next ? elide(String(next.title || ""), 28) : ""
  }

  return tasks && tasks.length > 0 ? String(tasks.length) : ""
}

function elide(text, limit) {
  if (text.length <= limit) return text
  return text.slice(0, Math.max(1, limit - 1)) + "…"
}

function overdueCount(tasks, now) {
  var count = 0
  for (var i = 0; i < (tasks || []).length; i++) {
    if (isOverdue(tasks[i], now)) count++
  }
  return count
}

// ---- undo --------------------------------------------------------------

function undoSecondsLeft(deadlineMs, nowMs) {
  if (!deadlineMs) return 0
  return Math.max(0, Math.ceil((deadlineMs - (nowMs || Date.now())) / 1000))
}

function expirePending(list, nowMs) {
  var now = nowMs || Date.now()
  var due = []
  var remaining = []
  for (var i = 0; i < (list || []).length; i++) {
    var entry = list[i]
    if (entry && entry.deadline <= now) due.push(entry)
    else remaining.push(entry)
  }
  return { due: due, remaining: remaining }
}

function topPending(list) {
  return (list && list.length > 0) ? list[list.length - 1] : null
}

function dropTopPending(list) {
  return (list && list.length > 0) ? list.slice(0, list.length - 1) : []
}

function undoLabel(pending, secondsLeft) {
  if (!pending) return ""
  var name = elide(String(pending.title || ""), 26)
  return "Completed " + name
}

function heldSuffix(count) {
  return count > 1 ? "  +" + (count - 1) + " more" : ""
}

// ---- cache -------------------------------------------------------------

function parseCache(text) {
  var empty = {
    syncedAt: 0,
    inboxId: "",
    projects: [],
    tasks: [],
    tags: [],
    todayStamp: 0,
    queued: 0,
    authRequired: false,
    error: null
  }
  if (!text) return empty
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return empty
    return {
      syncedAt: Number(parsed.syncedAt || 0),
      inboxId: String(parsed.inboxId || ""),
      projects: parsed.projects || [],
      tasks: parsed.tasks || [],
      tags: parsed.tags || [],
      todayStamp: Number(parsed.todayStamp || 0),
      queued: Number(parsed.queued || 0),
      authRequired: !!parsed.authRequired,
      error: parsed.error || null
    }
  } catch (e) {
    return empty
  }
}

function staleMinutes(syncedAt, now) {
  if (!syncedAt) return -1
  return Math.floor(((now || Date.now()) - syncedAt) / 60000)
}

if (typeof module !== "undefined") {
  module.exports = {
    parseApiDate: parseApiDate,
    taskDueDate: taskDueDate,
    startOfDay: startOfDay,
    endOfDay: endOfDay,
    addDays: addDays,
    dateStamp: dateStamp,
    stampToDate: stampToDate,
    horizonDays: horizonDays,
    cycleHorizon: cycleHorizon,
    horizons: horizons,
    horizonIndex: horizonIndex,
    horizonForDue: horizonForDue,
    widerHorizon: widerHorizon,
    isOpen: isOpen,
    isOverdue: isOverdue,
    dueTasks: dueTasks,
    nextTask: nextTask,
    nextTaskTitle: nextTaskTitle,
    dueLabel: dueLabel,
    priorityRank: priorityRank,
    tagIndex: tagIndex,
    firstTag: firstTag,
    tagColor: tagColor,
    tagLabel: tagLabel,
    dueTier: dueTier,
    syncIntervalSeconds: syncIntervalSeconds,
    syncIntervalLabels: syncIntervalLabels,
    parseQuickAdd: parseQuickAdd,
    quickAddArgs: quickAddArgs,
    editLineFor: editLineFor,
    editArgs: editArgs,
    projectName: projectName,
    barLabel: barLabel,
    cycleBarLabel: cycleBarLabel,
    barLabelDescription: barLabelDescription,
    elide: elide,
    overdueCount: overdueCount,
    undoSecondsLeft: undoSecondsLeft,
    expirePending: expirePending,
    topPending: topPending,
    dropTopPending: dropTopPending,
    heldSuffix: heldSuffix,
    undoLabel: undoLabel,
    parseCache: parseCache,
    staleMinutes: staleMinutes
  }
}
