///|
pub(all) struct Witness {
  position : Int32
  time : Int64
}

///|
struct CandidateQueue {
  mut items : Array[Witness]
  mut head : Int32
}

///|
fn CandidateQueue::new() -> CandidateQueue {
  { items: [], head: 0, }
}

///|
/// Advancing a logical head avoids shifting all retained candidates per event.
/// Compact after at least 32 consumed entries and at least half the allocation.
fn CandidateQueue::commit(
  self : CandidateQueue,
  head : Int32,
  added : Witness?,
) -> Unit {
  self.head = head
  if self.head == self.items.length() {
    self.items = []
    self.head = 0
  } else if self.head >= 32 && self.head >= self.items.length() / 2 {
    self.items = self.items[self.head:].to_owned()
    self.head = 0
  }
  if added is Some(value) {
    self.items.push(value)
  }
}

///|
pub(all) struct MonitorStats {
  processed : Int32
  graph_nodes : Int32
  retained_candidates : Int32
  peak_candidates : Int32
  node_updates : Int64
}

///|
pub struct Decision {
  priv position : Int32
  priv time : Int64
  priv names : Array[String]
  priv values : Array[Bool]
}

///|
pub fn Decision::position(self : Decision) -> Int32 {
  self.position
}

///|
pub fn Decision::timestamp(self : Decision) -> Int64 {
  self.time
}

///|
pub fn Decision::values(self : Decision) -> Array[Bool] {
  self.values.copy()
}

///|
pub fn Decision::names(self : Decision) -> Array[String] {
  self.names.copy()
}

///|
pub fn Decision::value(self : Decision, name : String) -> Bool? {
  for i in 0..<self.names.length() {
    if self.names[i] == name {
      return Some(self.values[i])
    }
  }
  None
}

///|
pub fn Decision::all_true(self : Decision) -> Bool {
  for value in self.values {
    if !value {
      return false
    }
  }
  true
}

///|
/// A monitor owns all mutable queues and prior values; plans may be shared.
/// It stores witnesses, not the complete input trace. One push is atomic on
/// validation or capacity errors: callers may retry the same timestamp.
pub struct Monitor {
  priv plan : Plan
  priv queues : Array[CandidateQueue]
  priv staged_heads : Array[Int32]
  priv staged_additions : Array[Witness?]
  priv mut last_values : Array[Bool]
  priv mut scratch_values : Array[Bool]
  priv mut witnesses : Array[Witness?]
  priv mut barriers : Array[Witness?]
  priv mut last_time : Int64?
  priv mut processed : Int32
  priv mut retained : Int32
  priv mut peak : Int32
}

///|
pub fn Monitor::new(plan : Plan) -> Monitor {
  let queues : Array[CandidateQueue] = []
  for _ in plan.nodes {
    queues.push(CandidateQueue::new())
  }
  {
    plan,
    queues,
    staged_heads: Array::make(plan.nodes.length(), 0),
    staged_additions: Array::make(plan.nodes.length(), None),
    last_values: Array::make(plan.nodes.length(), false),
    scratch_values: Array::make(plan.nodes.length(), false),
    witnesses: Array::make(plan.nodes.length(), None),
    barriers: Array::make(plan.nodes.length(), None),
    last_time: None,
    processed: 0,
    retained: 0,
    peak: 0,
  }
}

///|
pub fn Monitor::stats(self : Monitor) -> MonitorStats {
  {
    processed: self.processed,
    graph_nodes: self.plan.nodes.length(),
    retained_candidates: self.retained,
    peak_candidates: self.peak,
    node_updates: self.processed.to_int64() *
    self.plan.nodes.length().to_int64(),
  }
}

///|
pub fn Monitor::plan(self : Monitor) -> Plan {
  self.plan
}

///|
pub fn Monitor::push(
  self : Monitor,
  event : Observation,
) -> Result[Decision, MonitorError] {
  if self.processed >= self.plan.limits.events {
    return Err(ResourceLimit("monitor event count"))
  }
  if self.last_time is Some(previous) && event.time <= previous {
    return Err(InvalidTimestamp(self.processed))
  }
  match self.plan.validate_observation(event, self.processed) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let size = self.plan.nodes.length()
  let values = self.scratch_values
  let heads = self.staged_heads
  let additions = self.staged_additions
  let witnesses : Array[Witness?] = Array::make(size, None)
  let barriers = self.barriers.copy()
  let mut retained = 0
  let current = Witness::{ position: self.processed, time: event.time, }
  for id in 0..<size {
    let node = self.plan.nodes[id]
    match node {
      Literal(value) => values[id] = value
      Input(name) => values[id] = event.values.get(name).unwrap()
      Neg(child) => values[id] = !values[child]
      Both(a, b) => values[id] = values[a] && values[b]
      Either(a, b) => values[id] = values[a] || values[b]
      Implication(a, b) => values[id] = !values[a] || values[b]
      Prior(child) => {
        values[id] = self.processed > 0 && self.last_values[child]
        witnesses[id] = self.last_time.map(time => Witness::{
          position: self.processed - 1,
          time,
        })
      }
      AnyPast(window, child)
      | AllPast(window, child)
      | SincePast(window, child, _) => {
        let queue = self.queues[id]
        let mut head = queue.head
        let universal = node is AllPast(_, _)
        let mut add = if universal { !values[child] } else { values[child] }
        match node {
          SincePast(_, left, right) => {
            if !values[left] {
              head = queue.items.length()
              barriers[id] = Some(current)
            }
            add = values[right]
          }
          _ => ()
        }
        head = queue.first_live(head, event.time, window.upper)
        heads[id] = head
        additions[id] = if add { Some(current) } else { None }
        let candidate = if head < queue.items.length() {
          Some(queue.items[head])
        } else {
          additions[id]
        }
        let eligible = match candidate {
          Some(value) if event.time - value.time >= window.lower => Some(value)
          _ => None
        }
        witnesses[id] = eligible
        values[id] = if universal {
          eligible is None
        } else {
          eligible is Some(_)
        }
        retained += queue.items.length() - head + (if add { 1 } else { 0 })
        if retained > self.plan.limits.candidates {
          return Err(ResourceLimit("retained temporal candidates"))
        }
      }
    }
  }
  // The compiler records exactly the nodes owning temporal queues.
  for id in self.plan.temporal_nodes {
    self.queues[id].commit(heads[id], additions[id])
  }
  let output : Array[Bool] = []
  for root in self.plan.roots {
    output.push(values[root])
  }
  let decision = Decision::{
    position: self.processed,
    time: event.time,
    names: self.plan.names.copy(),
    values: output,
  }
  let previous_values = self.last_values
  self.last_values = values
  self.scratch_values = previous_values
  self.witnesses = witnesses
  self.barriers = barriers
  self.last_time = Some(event.time)
  self.processed += 1
  self.retained = retained
  if retained > self.peak {
    self.peak = retained
  }
  Ok(decision)
}

///|
pub fn Monitor::last_decision(self : Monitor) -> Decision? {
  match self.last_time {
    None => None
    Some(time) => {
      let values : Array[Bool] = []
      for root in self.plan.roots {
        values.push(self.last_values[root])
      }
      Some({
        position: self.processed - 1,
        time,
        names: self.plan.names.copy(),
        values,
      })
    }
  }
}

///|
/// Fast paths cover no expiration, one expiration and a fully expired queue.
/// Larger partial expiration jumps use lower-bound search instead of scanning.
fn CandidateQueue::first_live(
  self : CandidateQueue,
  head : Int32,
  time : Int64,
  upper : Int64,
) -> Int32 {
  let end = self.items.length()
  if head == end || time - self.items[head].time <= upper {
    return head
  }
  if time - self.items[end - 1].time > upper {
    return end
  }
  let mut low = head + 1
  if time - self.items[low].time <= upper {
    return low
  }
  let mut high = end - 1
  while low < high {
    let middle = low + (high - low) / 2
    if time - self.items[middle].time > upper {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low
}
