///|
/// Reproducible synthetic workloads model application records; they do not
/// claim deployment on a physical device or production service.
pub struct Scenario {
  priv name : String
  priv rules : Array[(String, String)]
  priv records : Array[@mtl.Observation]
}

///|
pub fn Scenario::name(self : Scenario) -> String {
  self.name
}

///|
pub fn Scenario::rules(self : Scenario) -> Array[(String, String)] {
  self.rules.copy()
}

///|
pub fn Scenario::trace(self : Scenario) -> Array[@mtl.Observation] {
  self.records.copy()
}

///|
pub fn Scenario::plan(self : Scenario) -> Result[@mtl.Plan, @mtl.MonitorError] {
  @mtl.Plan::from_strings(self.rules)
}

///|
pub fn Scenario::new(
  name : String,
  count : Int32,
) -> Result[Scenario, @mtl.MonitorError] {
  if count < 1 || count > 1000000 {
    return Err(@mtl.ResourceLimit("scenario count must be 1..1000000"))
  }
  match name {
    "handshake" => Ok(handshake(count))
    "lease" => Ok(lease(count))
    "recovery" => Ok(recovery(count))
    _ => Err(@mtl.InvalidData("unknown scenario: " + name))
  }
}

///|
fn record(time : Int32, values : Array[(String, Bool)]) -> @mtl.Observation {
  @mtl.Observation::new(time.to_int64(), Map(values)).unwrap()
}

///|
fn handshake(count : Int32) -> Scenario {
  let rules = [
    ("send_has_handshake", "send -> once[1,12] handshake"),
    ("send_has_auth", "send -> once[0,12] auth"),
    ("connected_since_auth", "send -> (connected since[0,12] auth)"),
    ("no_recent_error", "send -> historically[0,5] !error"),
    ("audit_handshake", "once[1,12] handshake"),
  ]
  let records = Array::makei(count, i => {
    let cycle = i % 24
    record(i, [
      ("handshake", cycle == 1),
      ("auth", cycle == 3),
      ("connected", cycle >= 1 && cycle < 19),
      ("send", cycle == 2 || cycle == 5 || cycle == 16 || cycle == 22),
      ("error", cycle == 14),
    ])
  })
  { name: "handshake", rules, records, }
}

///|
fn lease(count : Int32) -> Scenario {
  let rules = [
    ("work_has_lease", "working -> once[0,8] renew"),
    ("work_not_revoked", "working -> (allowed since[0,8] renew)"),
    ("no_recent_conflict", "working -> historically[0,4] !conflict"),
    ("renewal_audit", "once[0,8] renew"),
    ("work_transition", "working -> (previous working | renew)"),
  ]
  let records = Array::makei(count, i => {
    let cycle = i % 30
    record(i * 2, [
      ("renew", cycle == 0 || cycle == 3 || cycle == 15),
      ("working", cycle < 12 || (cycle >= 15 && cycle < 24)),
      ("allowed", cycle != 19 && cycle != 20),
      ("conflict", cycle == 8 || cycle == 22),
    ])
  })
  { name: "lease", rules, records, }
}

///|
fn recovery(count : Int32) -> Scenario {
  let rules = [
    ("recovery_has_alarm", "recovered -> once[1,20] alarm"),
    ("recovery_is_stable", "recovered -> historically[0,4] healthy"),
    ("stable_since_reset", "recovered -> (healthy since[2,20] reset)"),
    ("alarm_audit", "once[1,20] alarm"),
    ("nested_alarm", "once[0,8] (alarm & previous healthy)"),
  ]
  let records = Array::makei(count, i => {
    let cycle = i % 40
    // Irregular gaps distinguish sampled observations from persistent signals.
    let time = i * 2 + i / 7
    record(time, [
      ("alarm", cycle == 4 || cycle == 25),
      ("reset", cycle == 5 || cycle == 26),
      ("healthy", !(cycle >= 3 && cycle <= 5) && cycle != 28),
      ("recovered", cycle == 8 || cycle == 14 || cycle == 29 || cycle == 36),
    ])
  })
  { name: "recovery", rules, records, }
}

///|
pub(all) struct Summary {
  events : Int32
  checks : Int32
  failures : Int32
  checksum : Int32
  nodes : Int32
  peak_candidates : Int32
}

///|
/// The checksum includes every rule verdict in declared order. It is an
/// accidental-mismatch detector, not a cryptographic authenticity mechanism.
pub fn verdict_checksum(previous : Int32, values : Array[Bool]) -> Int32 {
  let mut checksum = previous
  for value in values {
    checksum = (checksum * 31 + (if value { 1 } else { 0 })) & 0x7fffffff
  }
  checksum
}

///|
pub fn Scenario::run(self : Scenario) -> Result[Summary, @mtl.MonitorError] {
  let plan = match self.plan() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let monitor = @mtl.Monitor::new(plan)
  let mut failures = 0
  let mut checksum = 1
  for observation in self.records {
    let decision = match monitor.push(observation) {
      Err(e) => return Err(e)
      Ok(value) => value
    }
    let values = decision.values()
    checksum = verdict_checksum(checksum, values)
    for value in values {
      if !value {
        failures += 1
      }
    }
  }
  Ok({
    events: self.records.length(),
    checks: self.records.length() * plan.rule_count(),
    failures,
    checksum,
    nodes: plan.node_count(),
    peak_candidates: monitor.stats().peak_candidates,
  })
}
