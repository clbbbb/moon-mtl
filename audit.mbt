///|
/// Per-rule operational counters. A failure run counts consecutive observed
/// false verdicts, not continuous elapsed-time violation duration.
pub(all) struct RuleSummary {
  name : String
  accepted : Int32
  rejected : Int32
  failure_runs : Int32
  current_failure_run : Int32
  longest_failure_run : Int32
  first_failure : Witness?
  last_failure : Witness?
  last_transition : Witness?
  latest : Bool?
}

///|
pub struct Audit {
  priv monitor : Monitor
  priv summaries : Array[RuleSummary]
}

///|
pub fn Audit::new(plan : Plan) -> Audit {
  let summaries = plan.names.map(name => RuleSummary::{
    name,
    accepted: 0,
    rejected: 0,
    failure_runs: 0,
    current_failure_run: 0,
    longest_failure_run: 0,
    first_failure: None,
    last_failure: None,
    last_transition: None,
    latest: None,
  })
  { monitor: Monitor::new(plan), summaries, }
}

///|
/// Update counters only after the monitor atomically accepts an observation.
/// The audit retains O(number of rules) counters and no observation history.
pub fn Audit::push(
  self : Audit,
  observation : Observation,
) -> Result[Decision, MonitorError] {
  let decision = match self.monitor.push(observation) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let witness = Witness::{ position: decision.position, time: decision.time, }
  for i in 0..<self.summaries.length() {
    let old = self.summaries[i]
    let value = decision.values[i]
    let run = if value { 0 } else { old.current_failure_run + 1 }
    self.summaries[i] = {
      name: old.name,
      accepted: old.accepted + (if value { 1 } else { 0 }),
      rejected: old.rejected + (if value { 0 } else { 1 }),
      failure_runs: old.failure_runs +
      (if !value && old.latest != Some(false) { 1 } else { 0 }),
      current_failure_run: run,
      longest_failure_run: if run > old.longest_failure_run {
        run
      } else {
        old.longest_failure_run
      },
      first_failure: if !value && old.first_failure is None {
        Some(witness)
      } else {
        old.first_failure
      },
      last_failure: if !value {
        Some(witness)
      } else {
        old.last_failure
      },
      last_transition: if old.latest is Some(previous) && previous != value {
        Some(witness)
      } else {
        old.last_transition
      },
      latest: Some(value),
    }
  }
  Ok(decision)
}

///|
pub fn Audit::summaries(self : Audit) -> Array[RuleSummary] {
  self.summaries.copy()
}

///|
pub fn Audit::summary(self : Audit, name : String) -> RuleSummary? {
  for summary in self.summaries {
    if summary.name == name {
      return Some(summary)
    }
  }
  None
}

///|
pub fn Audit::stats(self : Audit) -> MonitorStats {
  self.monitor.stats()
}

///|
pub fn Audit::explain(
  self : Audit,
  name : String,
) -> Result[Array[Evidence], MonitorError] {
  self.monitor.explain(name)
}

///|
pub fn Audit::last_decision(self : Audit) -> Decision? {
  self.monitor.last_decision()
}
