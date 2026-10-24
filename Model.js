.pragma library

function dateRange(now) {
  function day(offset) {
    return new Date(now + offset * 86400000).toISOString().slice(0, 10).replace(/-/g, "")
  }
  return day(-1) + "-" + day(7)
}

function clean(value) {
  return String(value || "").replace(/[\x00-\x1f\x7f]/g, " ").trim().slice(0, 160)
}

// ESPN flips the next bout to "in" (STATUS_PRE_FIGHT) as soon as the previous
// one ends, which can be long before anyone walks out. The fight's play log
// (newest first) says when walkouts and the first round actually start.
function fightState(status, details) {
  var type = status && status.type || {}
  var name = type.name || ""
  if (/CANCEL|POSTPON|DELAY|SUSPEND/i.test(name)) return "unavailable"
  if (type.completed === true || type.state === "post" || /END_OF_FIGHT|FIGHT_OVER/i.test(name)) return "post"
  if (type.state === "in") {
    var plays = (Array.isArray(details) ? details : []).map(function(d) {
      return String(d && d.type && d.type.text || "")
    }).join("|")
    if (/round start|round end|fight over/i.test(plays)) return "live"
    // STATUS_FIGHTERS_WALKING often lands before the first Walkout play.
    if (/WALK|INTRODUC/i.test(name) || /walkout|tale of the tape|staredown/i.test(plays)) return "walkout"
    // Any other pre-round state (pre-fight, fight open) is still waiting.
    return Number(status.period) > 0 && !/PRE_FIGHT/i.test(name) ? "live" : "waiting"
  }
  if (type.state === "pre") return "pre"
  return "unknown"
}

function parseScoreboard(raw) {
  var data = JSON.parse(raw)
  if (!data || !Array.isArray(data.events)) throw new Error("Missing events")
  return data.events.filter(function(event) {
    return event && event.id && Array.isArray(event.competitions)
      && !/contender series|road to ufc|ultimate fighter/i.test(event.name || "")
  }).map(function(event) {
    var fights = event.competitions.filter(function(fight) {
      return fight && fight.id && Array.isArray(fight.competitors) && fight.competitors.length === 2
    }).map(function(fight, index) {
      return {
        key: String(event.id) + ":" + String(fight.id),
        order: index,
        names: fight.competitors.map(function(c) {
          return clean(c.athlete && (c.athlete.displayName || c.athlete.fullName)) || "TBA"
        }),
        state: fightState(fight.status, fight.details),
        date: Date.parse(fight.date || fight.startDate || event.date) || 0
      }
    // The shell's sort is not stable, so fights sharing a start time
    // fall back to the feed order (main event last).
    }).sort(function(a, b) { return a.date - b.date || a.order - b.order })
    return {
      id: String(event.id),
      name: clean(event.name) || "UFC",
      date: Date.parse(event.date) || 0,
      state: fightState(event.status),
      fights: fights
    }
  }).filter(function(event) { return event.fights.length > 0 })
}

function isOn(fight) {
  return fight.state === "live" || fight.state === "walkout"
}

function isAhead(fight) {
  return fight.state === "pre" || fight.state === "waiting"
}

function upcomingFights(event) {
  return event ? event.fights.filter(isAhead) : []
}

function chooseEvent(events, now) {
  var live = events.filter(function(e) { return e.fights.some(isOn) })
  if (live.length) return live[0]
  var active = events.filter(function(e) {
    return (isOn(e) || e.state === "waiting" || e.fights.some(function(f) { return f.state === "waiting" }))
      && e.fights.some(isAhead)
  }).sort(function(a, b) { return b.date - a.date })
  if (active.length) return active[0]
  var upcoming = events.filter(function(e) {
    return e.state !== "unavailable" && e.date >= now
      && e.fights.some(isAhead)
  }).sort(function(a, b) { return a.date - b.date })
  if (upcoming.length) return upcoming[0]
  return events.slice().sort(function(a, b) { return b.date - a.date })[0] || null
}

// Poll fast while a card is running or about to start, slowly otherwise, so
// alerts can stay on all week without hammering ESPN.
var FAST_POLL = 15000
var SLOW_POLL = 600000

function pollInterval(event, now) {
  if (!event) return SLOW_POLL
  if (event.fights.some(function(f) { return isOn(f) || f.state === "waiting" })) return FAST_POLL
  var ahead = event.fights.some(isAhead)
  return ahead && now >= event.date - 3600000 ? FAST_POLL : SLOW_POLL
}

function liveFights(event) {
  return event ? event.fights.filter(function(f) { return f.state === "live" }) : []
}

function walkoutFights(event) {
  return event ? event.fights.filter(function(f) { return f.state === "walkout" }) : []
}

// Seed the first successful poll silently; later polls alert once per bout
// (at walkouts, or at the start if walkouts were missed), including after a
// connection failure or a round break.
function updateAlerts(event, seen, initialized) {
  var next = {}
  for (var key in seen) next[key] = true
  var alerts = []
  ;(event ? event.fights.filter(isOn) : []).forEach(function(fight) {
    if (initialized && !next[fight.key]) alerts.push(fight)
    next[fight.key] = true
  })
  return { seen: next, alerts: alerts }
}

function notificationText(value) {
  return clean(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}
