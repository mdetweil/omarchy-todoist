// Tests for Model.js — run with: node --test tests/model.test.js
"use strict"

const { test } = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

// ---- date helpers -------------------------------------------------------

test("parseApiDate: all-day Todoist format", () => {
  const d = Model.parseApiDate("2026-08-15")
  assert.ok(d instanceof Date)
  assert.ok(!isNaN(d.getTime()))
})

test("parseApiDate: timed Todoist format", () => {
  const d = Model.parseApiDate("2026-08-15T14:30:00Z")
  assert.ok(d instanceof Date)
  assert.ok(!isNaN(d.getTime()))
})

test("parseApiDate: null/empty returns null", () => {
  assert.equal(Model.parseApiDate(null), null)
  assert.equal(Model.parseApiDate(""), null)
})

test("taskDueDate: all-day task reads the date part literally", () => {
  const task = { dueDate: "2026-08-15", isAllDay: true }
  const d = Model.taskDueDate(task)
  assert.equal(d.getFullYear(), 2026)
  assert.equal(d.getMonth(), 7) // 0-indexed August
  assert.equal(d.getDate(), 15)
})

test("taskDueDate: no dueDate returns null", () => {
  assert.equal(Model.taskDueDate({ title: "foo" }), null)
  assert.equal(Model.taskDueDate(null), null)
})

test("dateStamp: produces YYYYMMDD integer", () => {
  const d = new Date(2026, 7, 15) // Aug 15 2026
  assert.equal(Model.dateStamp(d), 20260815)
})

test("addDays: crossing month boundary", () => {
  const d = new Date(2026, 0, 31) // Jan 31
  const next = Model.addDays(d, 1)
  assert.equal(next.getMonth(), 1)
  assert.equal(next.getDate(), 1)
})

// ---- task filtering -----------------------------------------------------

const makeTask = (overrides) => Object.assign({
  id: "t1",
  title: "Test task",
  status: 0,
  priority: 0,
  tags: [],
  dueDate: "2026-08-15",
  isAllDay: true,
  sortOrder: 0,
  deleted: false,
}, overrides)

test("isOpen: todo task is open", () => {
  assert.ok(Model.isOpen(makeTask({ status: 0 })))
})

test("isOpen: done task is not open", () => {
  assert.ok(!Model.isOpen(makeTask({ status: 2 })))
})

test("isOpen: deleted task is not open", () => {
  assert.ok(!Model.isOpen(makeTask({ deleted: true })))
})

test("isOverdue: task due yesterday is overdue", () => {
  const yesterday = Model.addDays(new Date(), -1)
  const task = makeTask({
    dueDate: yesterday.getFullYear() + "-"
      + String(yesterday.getMonth() + 1).padStart(2, "0") + "-"
      + String(yesterday.getDate()).padStart(2, "0"),
    isAllDay: true,
  })
  assert.ok(Model.isOverdue(task, new Date()))
})

test("isOverdue: task due today is not overdue (all-day)", () => {
  const today = new Date()
  const task = makeTask({
    dueDate: today.getFullYear() + "-"
      + String(today.getMonth() + 1).padStart(2, "0") + "-"
      + String(today.getDate()).padStart(2, "0"),
    isAllDay: true,
  })
  assert.ok(!Model.isOverdue(task, today))
})

test("dueTasks: returns today's tasks sorted overdue first", () => {
  const today = new Date(2026, 7, 15)
  const yesterday = new Date(2026, 7, 14)

  const tasks = [
    makeTask({ id: "a", dueDate: "2026-08-15", isAllDay: true }),
    makeTask({ id: "b", dueDate: "2026-08-14", isAllDay: true }),
  ]
  const result = Model.dueTasks(tasks, { now: today, horizon: "Today", includeOverdue: true })
  assert.equal(result[0].id, "b") // overdue first
  assert.equal(result[1].id, "a")
})

test("dueTasks: excludes tasks without due date", () => {
  const today = new Date(2026, 7, 15)
  const tasks = [
    makeTask({ id: "no-due", dueDate: "" }),
    makeTask({ id: "has-due", dueDate: "2026-08-15", isAllDay: true }),
  ]
  const result = Model.dueTasks(tasks, { now: today, horizon: "Today" })
  assert.equal(result.length, 1)
  assert.equal(result[0].id, "has-due")
})

test("dueTasks: horizon Today excludes tomorrow", () => {
  const today = new Date(2026, 7, 15)
  const tasks = [
    makeTask({ id: "today", dueDate: "2026-08-15", isAllDay: true }),
    makeTask({ id: "tomorrow", dueDate: "2026-08-16", isAllDay: true }),
  ]
  const result = Model.dueTasks(tasks, { now: today, horizon: "Today", includeOverdue: false })
  assert.equal(result.length, 1)
  assert.equal(result[0].id, "today")
})

// ---- quick add parsing --------------------------------------------------

test("parseQuickAdd: extracts title, tag, priority, due", () => {
  const r = Model.parseQuickAdd("Pay rent #personal !1 tomorrow")
  assert.equal(r.title, "Pay rent")
  assert.deepEqual(r.tags, ["personal"])
  assert.equal(r.priority, 5)
  assert.equal(r.due, "tomorrow")
  assert.equal(r.dueGiven, true)
})

test("parseQuickAdd: no syntax gives plain title due today", () => {
  const r = Model.parseQuickAdd("Stand up meeting")
  assert.equal(r.title, "Stand up meeting")
  assert.equal(r.due, "today")
  assert.equal(r.dueGiven, false)
  assert.deepEqual(r.tags, [])
})

test("parseQuickAdd: interior 'today' is not a date", () => {
  const r = Model.parseQuickAdd("Plan today standup")
  assert.equal(r.title, "Plan today standup")
  assert.equal(r.dueGiven, false)
})

test("parseQuickAdd: preposition consumed with trailing date", () => {
  const r = Model.parseQuickAdd("Standup notes for today")
  assert.equal(r.title, "Standup notes")
  assert.equal(r.due, "today")
  assert.equal(r.dueGiven, true)
})

test("quickAddArgs: builds CLI argument array", () => {
  const args = Model.quickAddArgs("Buy milk #groceries tomorrow")
  assert.equal(args[0], "add")
  assert.equal(args[1], "Buy milk")
  assert.ok(args.includes("tomorrow"))
  assert.ok(args.includes("groceries"))
})

// ---- priority -----------------------------------------------------------

test("priorityRank: maps display priority values", () => {
  assert.equal(Model.priorityRank({ priority: 5 }), "high")
  assert.equal(Model.priorityRank({ priority: 3 }), "medium")
  assert.equal(Model.priorityRank({ priority: 1 }), "low")
  assert.equal(Model.priorityRank({ priority: 0 }), "none")
})

// ---- label (tag) index --------------------------------------------------

test("tagIndex: builds name lookup", () => {
  const tags = [
    { name: "work", label: "Work", color: "#ff0000" },
    { name: "personal", label: "Personal", color: "#00ff00" },
  ]
  const index = Model.tagIndex(tags)
  assert.ok("work" in index)
  assert.equal(index["work"].color, "#ff0000")
})

test("tagColor: returns color for first matching label", () => {
  const task = makeTask({ tags: ["work"] })
  const index = Model.tagIndex([{ name: "work", label: "Work", color: "#ff0000" }])
  assert.equal(Model.tagColor(task, index), "#ff0000")
})

test("tagColor: returns empty string when no labels", () => {
  const task = makeTask({ tags: [] })
  const index = Model.tagIndex([])
  assert.equal(Model.tagColor(task, index), "")
})

// ---- cache parsing ------------------------------------------------------

test("parseCache: empty string returns defaults", () => {
  const c = Model.parseCache("")
  assert.equal(c.syncedAt, 0)
  assert.deepEqual(c.tasks, [])
  assert.deepEqual(c.projects, [])
  assert.equal(c.authRequired, false)
})

test("parseCache: parses valid JSON", () => {
  const raw = JSON.stringify({
    syncedAt: 1000,
    tasks: [{ id: "t1" }],
    projects: [],
    tags: [],
    inboxId: "inbox",
    todayStamp: 20260815,
    queued: 0,
  })
  const c = Model.parseCache(raw)
  assert.equal(c.syncedAt, 1000)
  assert.equal(c.tasks.length, 1)
})

// ---- undo helpers -------------------------------------------------------

test("undoSecondsLeft: counts down from deadline", () => {
  const now = Date.now()
  assert.equal(Model.undoSecondsLeft(now + 5000, now), 5)
  assert.equal(Model.undoSecondsLeft(now - 1000, now), 0)
})

test("expirePending: splits due and remaining", () => {
  const now = Date.now()
  const list = [
    { deadline: now - 1000, title: "old" },
    { deadline: now + 5000, title: "new" },
  ]
  const result = Model.expirePending(list, now)
  assert.equal(result.due.length, 1)
  assert.equal(result.remaining.length, 1)
  assert.equal(result.due[0].title, "old")
})

// ---- bar label ----------------------------------------------------------

test("barLabel: Count mode returns task count", () => {
  const tasks = [makeTask({ id: "a" }), makeTask({ id: "b" })]
  assert.equal(Model.barLabel("Count", tasks, new Date()), "2")
})

test("barLabel: Count mode returns empty string for zero tasks", () => {
  assert.equal(Model.barLabel("Count", [], new Date()), "")
})

test("barLabel: Icon mode returns empty string", () => {
  const tasks = [makeTask({ id: "a" })]
  assert.equal(Model.barLabel("Icon", tasks, new Date()), "")
})
