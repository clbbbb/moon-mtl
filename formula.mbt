///|
/// Closed interval in the caller's nonnegative integer time unit.
pub struct Interval {
  priv lower : Int64
  priv upper : Int64
}

///|
pub(all) enum MonitorError {
  InvalidInterval
  InvalidTimestamp(Int32)
  MissingAtom(String, Int32)
  InvalidPosition(Int32)
  ResourceLimit(String)
  SyntaxError(Int32, String)
  InvalidData(String)
}

///|
pub fn Interval::new(
  lower : Int64,
  upper : Int64,
) -> Result[Interval, MonitorError] {
  if lower < 0L || upper < lower {
    Err(InvalidInterval)
  } else {
    Ok({ lower, upper, })
  }
}

///|
pub fn Interval::lower(self : Interval) -> Int64 {
  self.lower
}

///|
pub fn Interval::upper(self : Interval) -> Int64 {
  self.upper
}

///|
/// Pointwise past-time formulas. Since requires left at every observed position
/// strictly after its right-hand witness, including the current position.
pub(all) enum Formula {
  Constant(Bool)
  Atom(String)
  Not(Formula)
  And(Formula, Formula)
  Or(Formula, Formula)
  Implies(Formula, Formula)
  Previous(Formula)
  Once(Interval, Formula)
  Historically(Interval, Formula)
  Since(Interval, Formula, Formula)
}

///|
/// Own an immutable snapshot of the caller's valuation; absent is not false.
pub struct Observation {
  priv time : Int64
  priv values : Map[String, Bool]
}

///|
pub fn Observation::new(
  time : Int64,
  values : Map[String, Bool],
) -> Result[Observation, MonitorError] {
  if time < 0L {
    return Err(InvalidTimestamp(0))
  }
  if values.length() > 4096 {
    return Err(ResourceLimit("observation atom count"))
  }
  let copied : Map[String, Bool] = Map([])
  for name, value in values {
    if !valid_identifier(name) {
      return Err(InvalidData("invalid observation atom name"))
    }
    copied[name] = value
  }
  Ok({ time, values: copied, })
}

///|
pub fn Observation::timestamp(self : Observation) -> Int64 {
  self.time
}

///|
pub fn Observation::value(self : Observation, name : String) -> Bool? {
  self.values.get(name)
}
