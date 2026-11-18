///|
/// Independent semantic reference: deliberately enumerates witnesses and
/// intervening positions. It shares no execution caches with the online path.
pub fn evaluate_reference(
  formula : Formula,
  trace : Array[Observation],
  position : Int32,
  steps~ : Int32 = 1000000,
) -> Result[Bool, MonitorError] {
  let plan = match Plan::new([("reference", formula)]) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let evaluator = match Reference::new(plan, trace, steps~) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  evaluator.evaluate(position).map(decision => decision.values[0])
}

///|
priv struct ReferenceWork {
  mut remaining : Int32
}

///|
/// Validates and owns the trace array once. Each evaluate call has an explicit
/// recursion-work ceiling; nested historical formulas cannot run unbounded.
pub struct Reference {
  priv plan : Plan
  priv trace : Array[Observation]
  priv limit : Int32
  priv mut used : Int32
}

///|
pub fn Reference::new(
  plan : Plan,
  trace : Array[Observation],
  steps~ : Int32 = 1000000,
) -> Result[Reference, MonitorError] {
  if steps < 1 || steps > 100000000 {
    return Err(ResourceLimit("reference steps must be 1..100000000"))
  }
  match plan.validate_trace(trace) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok({ plan, trace: trace.copy(), limit: steps, used: 0, })
}

///|
pub fn Reference::last_steps(self : Reference) -> Int32 {
  self.used
}

///|
pub fn Reference::evaluate(
  self : Reference,
  position : Int32,
) -> Result[Decision, MonitorError] {
  if position < 0 || position >= self.trace.length() {
    return Err(InvalidPosition(position))
  }
  let work = ReferenceWork::{ remaining: self.limit, }
  let values : Array[Bool] = []
  for formula in self.plan.formulas {
    match reference_at(formula, self.trace, position, work) {
      Err(error) => {
        self.used = self.limit - work.remaining
        return Err(error)
      }
      Ok(value) => values.push(value)
    }
  }
  self.used = self.limit - work.remaining
  Ok({
    position,
    time: self.trace[position].time,
    names: self.plan.names.copy(),
    values,
  })
}

///|
fn reference_at(
  formula : Formula,
  trace : Array[Observation],
  at : Int32,
  work : ReferenceWork,
) -> Result[Bool, MonitorError] {
  if work.remaining == 0 {
    return Err(ResourceLimit("reference evaluation steps"))
  }
  work.remaining -= 1
  match formula {
    Constant(value) => Ok(value)
    Atom(name) =>
      match trace[at].values.get(name) {
        None => Err(MissingAtom(name, at))
        Some(value) => Ok(value)
      }
    Not(child) => reference_at(child, trace, at, work).map(value => !value)
    And(left, right) | Or(left, right) | Implies(left, right) => {
      let a = match reference_at(left, trace, at, work) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let b = match reference_at(right, trace, at, work) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      match formula {
        And(_, _) => Ok(a && b)
        Or(_, _) => Ok(a || b)
        _ => Ok(!a || b)
      }
    }
    Previous(child) =>
      if at == 0 {
        Ok(false)
      } else {
        reference_at(child, trace, at - 1, work)
      }
    Once(window, child) | Historically(window, child) => {
      let universal = formula is Historically(_, _)
      let mut result = universal
      for j in 0..<(at + 1) {
        let age = trace[at].time - trace[j].time
        if age >= window.lower && age <= window.upper {
          let value = match reference_at(child, trace, j, work) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          if universal {
            result = result && value
          } else {
            result = result || value
          }
        }
      }
      Ok(result)
    }
    Since(window, left, right) => {
      let mut result = false
      for j in 0..<(at + 1) {
        let age = trace[at].time - trace[j].time
        if age >= window.lower && age <= window.upper {
          let mut valid = match reference_at(right, trace, j, work) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          for k in (j + 1)..<(at + 1) {
            let value = match reference_at(left, trace, k, work) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            valid = valid && value
          }
          result = result || valid
        }
      }
      Ok(result)
    }
  }
}
