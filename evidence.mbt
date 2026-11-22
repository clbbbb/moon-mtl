///|
/// One relevant graph evaluation. Offsets describe ages, not absolute times.
/// An absent witness for a false Once/Since describes absence over the observed
/// window, not proof that no unobserved real-world event occurred.
pub(all) struct Evidence {
  node : Int32
  kind : String
  value : Bool
  position : Int32
  time : Int64
  lower_age : Int64?
  upper_age : Int64?
  witness : Witness?
  barrier : Witness?
}

///|
fn node_kind(node : Node) -> String {
  match node {
    Literal(_) => "constant"
    Input(name) => "atom:" + name
    Neg(_) => "not"
    Both(_, _) => "and"
    Either(_, _) => "or"
    Implication(_, _) => "implies"
    Prior(_) => "previous"
    AnyPast(_, _) => "once"
    AllPast(_, _) => "historically"
    SincePast(_, _, _) => "since"
  }
}

///|
fn node_interval(node : Node) -> Interval? {
  match node {
    AnyPast(window, _) | AllPast(window, _) | SincePast(window, _, _) =>
      Some(window)
    _ => None
  }
}

///|
/// Explain the most recent rule decision. Boolean branches select sufficient
/// evidence; temporal nodes stop at the historical witness instead of wrongly
/// explaining their child's value at the current observation.
pub fn Monitor::explain(
  self : Monitor,
  name : String,
) -> Result[Array[Evidence], MonitorError] {
  if self.processed == 0 {
    return Err(InvalidPosition(0))
  }
  let index = match self.plan.rule_index(name) {
    Some(index) => index
    None => return Err(SyntaxError(0, "unknown rule " + name))
  }
  let root = self.plan.roots[index]
  let pending = [root]
  let visited = Array::make(self.plan.nodes.length(), false)
  let result : Array[Evidence] = []
  while !pending.is_empty() {
    let id = pending.pop().unwrap()
    if visited[id] {
      continue
    }
    visited[id] = true
    let node = self.plan.nodes[id]
    let value = self.last_values[id]
    let window = node_interval(node)
    result.push({
      node: id,
      kind: node_kind(node),
      value,
      position: self.processed - 1,
      time: self.last_time.unwrap(),
      lower_age: window.map(w => w.lower),
      upper_age: window.map(w => w.upper),
      witness: self.witnesses[id],
      barrier: self.barriers[id],
    })
    match node {
      Neg(child) => pending.push(child)
      Both(a, b) =>
        if value {
          pending.push(b)
          pending.push(a)
        } else {
          pending.push(if !self.last_values[a] { a } else { b })
        }
      Either(a, b) =>
        if !value {
          pending.push(b)
          pending.push(a)
        } else {
          pending.push(if self.last_values[a] { a } else { b })
        }
      Implication(a, b) =>
        if !value {
          pending.push(b)
          pending.push(a)
        } else {
          pending.push(if !self.last_values[a] { a } else { b })
        }
      _ => ()
    }
  }
  Ok(result)
}

///|
/// Recover the immutable AST corresponding to each topologically ordered node.
/// This retains sharing but has no online Boolean values or witness queues.
fn Plan::node_formulas(self : Plan) -> Array[Formula] {
  let formulas : Array[Formula] = []
  for node in self.nodes {
    let formula = match node {
      Literal(v) => Constant(v)
      Input(name) => Atom(name)
      Neg(c) => Not(formulas[c])
      Both(a, b) => And(formulas[a], formulas[b])
      Either(a, b) => Or(formulas[a], formulas[b])
      Implication(a, b) => Implies(formulas[a], formulas[b])
      Prior(c) => Previous(formulas[c])
      AnyPast(w, c) => Once(w, formulas[c])
      AllPast(w, c) => Historically(w, formulas[c])
      SincePast(w, a, b) => Since(w, formulas[a], formulas[b])
    }
    formulas.push(formula)
  }
  formulas
}

///|
/// Independently re-evaluate a complete decision against its input prefix.
/// Matching verdicts says nothing about unobserved executions or authenticity.
pub fn Plan::verify_decision(
  self : Plan,
  trace : Array[Observation],
  decision : Decision,
) -> Result[Bool, MonitorError] {
  match self.validate_trace(trace) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  // This synchronous check uses the already validated trace without retaining it.
  Reference::{ plan: self, trace, limit: 1000000, used: 0, }.verify(decision)
}

///|
pub fn Reference::verify(
  self : Reference,
  decision : Decision,
) -> Result[Bool, MonitorError] {
  let position = decision.position
  if position < 0 || position >= self.trace.length() {
    return Err(InvalidPosition(position))
  }
  if decision.time != self.trace[position].time ||
    decision.names != self.plan.names ||
    decision.values.length() != self.plan.roots.length() {
    return Ok(false)
  }
  match self.evaluate(position) {
    Err(e) => return Err(e)
    Ok(expected) => return Ok(expected.values == decision.values)
  }
}

///|
/// Verify reported node values and any witness/barrier against actual records.
/// This validates fragments, not completeness of a caller-supplied explanation.
pub fn Plan::verify_evidence(
  self : Plan,
  trace : Array[Observation],
  evidence : Array[Evidence],
) -> Result[Bool, MonitorError] {
  match self.validate_trace(trace) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if evidence.length() > self.nodes.length() {
    return Err(ResourceLimit("evidence length"))
  }
  let formulas = self.node_formulas()
  let work = ReferenceWork::{ remaining: 1000000, }
  let seen = Array::make(self.nodes.length(), false)
  for fragment in evidence {
    let id = fragment.node
    let at = fragment.position
    if id < 0 || id >= self.nodes.length() || at < 0 || at >= trace.length() {
      return Ok(false)
    }
    if seen[id] {
      return Ok(false)
    }
    seen[id] = true
    let node = self.nodes[id]
    if fragment.kind != node_kind(node) || fragment.time != trace[at].time {
      return Ok(false)
    }
    let window = node_interval(node)
    if fragment.lower_age != window.map(w => w.lower) ||
      fragment.upper_age != window.map(w => w.upper) {
      return Ok(false)
    }
    let actual = match reference_at(formulas[id], trace, at, work) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    if fragment.value != actual {
      return Ok(false)
    }
    match (node, fragment.witness) {
      (Prior(_), witness) =>
        if at == 0 {
          if witness is Some(_) {
            return Ok(false)
          }
        } else {
          match witness {
            Some(w) if w.position == at - 1 && w.time == trace[at - 1].time =>
              ()
            _ => return Ok(false)
          }
        }
      (AnyPast(w, child), witness)
      | (AllPast(w, child), witness)
      | (SincePast(w, _, child), witness) => {
        let expected_witness = if node is AllPast(_, _) {
          !actual
        } else {
          actual
        }
        if expected_witness != (witness is Some(_)) {
          return Ok(false)
        }
        if witness is Some(found) {
          let j = found.position
          if j < 0 || j > at || found.time != trace[j].time {
            return Ok(false)
          }
          let age = trace[at].time - found.time
          if age < w.lower || age > w.upper {
            return Ok(false)
          }
          let child_value = match
            reference_at(formulas[child], trace, j, work) {
            Err(e) => return Err(e)
            Ok(v) => v
          }
          if child_value == (node is AllPast(_, _)) {
            return Ok(false)
          }
          match node {
            SincePast(_, left, _) =>
              for k in (j + 1)..<(at + 1) {
                match reference_at(formulas[left], trace, k, work) {
                  Err(e) => return Err(e)
                  Ok(false) => return Ok(false)
                  Ok(true) => ()
                }
              }
            _ => ()
          }
        }
      }
      (_, None) => ()
      _ => return Ok(false)
    }
    match (node, fragment.barrier) {
      (SincePast(_, left, _), Some(found)) => {
        let j = found.position
        if j < 0 || j > at || found.time != trace[j].time {
          return Ok(false)
        }
        match reference_at(formulas[left], trace, j, work) {
          Err(e) => return Err(e)
          Ok(true) => return Ok(false)
          Ok(false) => ()
        }
      }
      (_, None) => ()
      _ => return Ok(false)
    }
  }
  Ok(true)
}
