const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const { test } = require("node:test")

const Model = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, "Model.js"), "utf8").replace(/^\.pragma library\s*/, ""), Model)

function fight(id, state, extra = {}) {
  return {
    id, date: "2026-10-25T00:00Z",
    competitors: [{ athlete: { displayName: "Fighter A" } }, { athlete: { displayName: "Fighter B" } }],
    status: { period: state === "in" ? 1 : 0, type: { state, name: state === "in" ? "STATUS_IN_PROGRESS_2" : "STATUS_SCHEDULED", ...extra } }
  }
}

function card(competitions, extra = {}) {
  return { id: "ufc1", name: "UFC Test Card", date: "2026-10-25T00:00Z",
    status: { type: { state: "in" } }, competitions, ...extra }
}

function parse(event) { return Model.parseScoreboard(JSON.stringify({ events: [event] }))[0] }

test("alerts for the next bout once, including after a round break and a missed poll", () => {
  const first = parse(card([fight("1", "in"), fight("2", "pre")]))
  let result = Model.updateAlerts(first, {}, false)
  assert.equal(result.alerts.length, 0, "an already live bout seeds the baseline")
  result = Model.updateAlerts(first, result.seen, true)
  assert.equal(result.alerts.length, 0)
  const gap = parse(card([fight("1", "post"), fight("2", "pre")]))
  result = Model.updateAlerts(gap, result.seen, true)
  assert.equal(result.alerts.length, 0, "between fights stays quiet")
  const next = parse(card([fight("1", "post"), fight("2", "in")]))
  result = Model.updateAlerts(next, result.seen, true)
  assert.equal(result.alerts.length, 1)
  assert.equal(result.alerts[0].key, "ufc1:2")
  result = Model.updateAlerts(null, result.seen, true)
  result = Model.updateAlerts(next, result.seen, true)
  assert.equal(result.alerts.length, 0, "a missing poll cannot retrigger the bell")
  const roundBreak = parse(card([fight("2", "in", { name: "STATUS_END_OF_ROUND" })]))
  assert.equal(Model.updateAlerts(roundBreak, result.seen, true).alerts.length, 0)
})

test("first fight alerts when monitoring began before the card", () => {
  let result = Model.updateAlerts(parse(card([fight("1", "pre")])), {}, false)
  result = Model.updateAlerts(parse(card([fight("1", "in")])), result.seen, true)
  assert.equal(result.alerts.length, 1)
})

test("a live fight wins over an upcoming card and a completed card", () => {
  const upcoming = parse(card([fight("2", "pre")], { id: "future", date: "2026-11-01T00:00Z", status: { type: { state: "pre" } } }))
  const finished = parse(card([fight("1", "post")], { id: "old", status: { type: { state: "post" } } }))
  const live = parse(card([fight("3", "in")]))
  assert.equal(Model.chooseEvent([upcoming, finished, live], Date.parse("2026-10-25T01:00Z")).id, "ufc1")
  assert.equal(Model.chooseEvent([upcoming, finished], Date.parse("2026-10-25T01:00Z")).id, "future")
  const gap = parse(card([fight("1", "post"), fight("2", "pre")]))
  assert.equal(Model.chooseEvent([upcoming, gap], Date.parse("2026-10-25T01:00Z")).id, "ufc1")
})

test("canceled, postponed, completed and unknown fights cannot ring", () => {
  for (const name of ["STATUS_CANCELED", "STATUS_POSTPONED", "STATUS_DELAYED", "STATUS_SUSPENDED"])
    assert.equal(Model.liveFights(parse(card([fight("1", "in", { name })]))).length, 0)
  assert.equal(Model.liveFights(parse(card([fight("1", "in", { completed: true })]))).length, 0)
  assert.equal(Model.fightState({}), "unknown")
})

test("no-event responses are valid; malformed responses fail without losing seen bouts", () => {
  assert.equal(Model.parseScoreboard('{"events":[]}').length, 0)
  assert.equal(Model.chooseEvent([], Date.now()), null)
  for (const raw of ["<html>error</html>", "null", "{}", '{"events":null}'])
    assert.throws(() => Model.parseScoreboard(raw))
  assert.equal(Model.parseScoreboard('{"events":[null,{}, {"id":"x","competitions":[]}]}').length, 0)
  assert.equal(Model.parseScoreboard(JSON.stringify({ events: [card([fight("1", "in")], { name: "Dana White's Contender Series" })] })).length, 0)
})

test("dates cover midnight and year rollover; notifications escape external text", () => {
  assert.equal(Model.dateRange(Date.parse("2026-12-31T23:59Z")), "20261230-20270107")
  assert.equal(Model.dateRange(Date.parse("2027-01-01T00:01Z")), "20261231-20270108")
  assert.equal(Model.notificationText("A <b>& B\n"), "A &lt;b&gt;&amp; B")
  const event = parse(card([fight("1", "in")]))
  assert.equal("winner" in event.fights[0], false)
  assert.equal("results" in event.fights[0], false)
})

test("fights sharing a start time keep the card order", () => {
  const fights = ["1", "2", "3", "4", "5"].map(id => fight(id, "pre"))
  fights[0].date = "2026-10-25T02:00Z"
  const event = parse(card(fights))
  assert.equal(event.fights.map(f => f.key).join(), "ufc1:2,ufc1:3,ufc1:4,ufc1:5,ufc1:1")
})

test("pre-fight waits quietly; the bell rings at the first walkout, once", () => {
  const plays = (...names) => names.reverse().map((text, i) => ({ id: String(i), type: { id: "0", text } }))
  let result = Model.updateAlerts(parse(card([fight("1", "in"), fight("2", "pre")])), {}, false)
  const waiting = parse(card([fight("1", "post"), fight("2", "in", { name: "STATUS_PRE_FIGHT" })]))
  assert.equal(waiting.fights[1].state, "waiting")
  assert.equal(Model.upcomingFights(waiting).length, 1, "a pre-fight bout is still up next")
  assert.equal(Model.chooseEvent([waiting], Date.now()).id, "ufc1")
  result = Model.updateAlerts(waiting, result.seen, true)
  assert.equal(result.alerts.length, 0, "no bell before walkouts")

  const walkFight = fight("2", "in", { name: "STATUS_PRE_FIGHT" })
  walkFight.details = plays("Fight Open", "Walkout")
  const walk = parse(card([fight("1", "post"), walkFight]))
  assert.equal(walk.fights[1].state, "walkout")
  assert.equal(Model.liveFights(walk).length, 0, "walkouts are not LIVE NOW")
  result = Model.updateAlerts(walk, result.seen, true)
  assert.equal(result.alerts.length, 1)
  assert.equal(result.alerts[0].state, "walkout")

  const walking = fight("2", "in", { name: "STATUS_FIGHTERS_WALKING" })
  walking.details = plays("Fight Open")
  assert.equal(parse(card([walking])).fights[0].state, "walkout", "ESPN's walkout status counts before the play is logged")
  const opened = fight("2", "in", { name: "STATUS_FIGHT_OPEN" })
  opened.details = plays("Fight Open")
  opened.status.period = 0
  assert.equal(parse(card([opened])).fights[0].state, "waiting", "unknown pre-round states are not live")

  const liveFight = fight("2", "in")
  liveFight.details = plays("Fight Open", "Walkout", "Walkout", "Tale of the tape", "Staredown", "Round Start")
  const live = parse(card([fight("1", "post"), liveFight]))
  assert.equal(Model.liveFights(live).length, 1)
  assert.equal(Model.updateAlerts(live, result.seen, true).alerts.length, 0, "no second bell when it starts")
  assert.equal(Model.fightState({ type: { state: "in", name: "STATUS_END_OF_FIGHT" } }), "post")
})

test("polls fast during a card and slowly the rest of the week", () => {
  const now = Date.parse("2026-10-25T00:00Z")
  const ev = (fights, date) => parse(card(fights, { date }))
  assert.equal(Model.pollInterval(null, now), Model.SLOW_POLL)
  assert.equal(Model.pollInterval(ev([fight("1", "pre")], "2026-10-28T00:00Z"), now), Model.SLOW_POLL, "next card days away")
  assert.equal(Model.pollInterval(ev([fight("1", "pre")], "2026-10-25T00:30Z"), now), Model.FAST_POLL, "card within the hour")
  assert.equal(Model.pollInterval(ev([fight("1", "post"), fight("2", "pre")], "2026-10-24T22:00Z"), now), Model.FAST_POLL, "between fights")
  assert.equal(Model.pollInterval(ev([fight("1", "post"), fight("2", "in", { name: "STATUS_PRE_FIGHT" })], "2026-10-24T22:00Z"), now), Model.FAST_POLL)
  assert.equal(Model.pollInterval(ev([fight("1", "post")], "2026-10-24T22:00Z"), now), Model.SLOW_POLL, "card finished")
})

test("manifest entry points exist and match the service and widget", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "manifest.json"), "utf8"))
  assert.equal(manifest.id, "zakarch.fight-bell")
  for (const entry of Object.values(manifest.entryPoints))
    assert.ok(fs.existsSync(path.join(__dirname, entry)))
})
