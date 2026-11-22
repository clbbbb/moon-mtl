///|
/// Decode verdicts in this plan's order. Decoding validates structure only;
/// verify_decision checks the claim against actual observations independently.
pub fn Plan::decision_from_json(
  self : Plan,
  text : String,
) -> Result[Decision, MonitorError] {
  let json = match read_json(text, 1048576) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let fields = match json {
    Object(fields) if fields.length() == 3 => fields
    _ =>
      return Err(InvalidData("decision requires position, time and verdicts"))
  }
  let position = match fields.get("position") {
    Some(Number(number, ..)) if number >= 0.0 &&
      number < self.limits.events.to_double() => {
      let integer = number.to_int()
      if integer.to_double() != number {
        return Err(InvalidData("decision position must be an integer"))
      }
      integer
    }
    _ =>
      return Err(InvalidData("decision position is outside the event budget"))
  }
  let time = match fields.get("time") {
    Some(String(text)) =>
      match decimal_timestamp(text) {
        Err(e) => return Err(e)
        Ok(value) => value
      }
    _ => return Err(InvalidData("decision time must be a decimal string"))
  }
  let verdicts = match fields.get("verdicts") {
    Some(Object(verdicts)) if verdicts.length() == self.names.length() =>
      verdicts
    _ => return Err(InvalidData("decision verdict count differs from plan"))
  }
  let values : Array[Bool] = []
  for name in self.names {
    match verdicts.get(name) {
      Some(True) => values.push(true)
      Some(False) => values.push(false)
      _ =>
        return Err(
          InvalidData("decision is missing a Boolean verdict for " + name),
        )
    }
  }
  Ok({ position, time, names: self.names, values, })
}
