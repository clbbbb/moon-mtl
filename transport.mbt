///|
// Retain the explicit input depth limit while the RC deprecates its label.
#warnings("-deprecated")
fn read_json(text : String, maximum : Int32) -> Result[Json, MonitorError] {
  if text.length() > maximum {
    return Err(ResourceLimit("JSON input length"))
  }
  Ok(@json.parse(text[:], max_nesting_depth=16, reject_duplicate_keys=true)) catch {
    _ => Err(InvalidData("invalid JSON, duplicate keys, or excessive nesting"))
  }
}

///|
fn decimal_timestamp(text : String) -> Result[Int64, MonitorError] {
  if text.length() == 0 || text.length() > 19 {
    return Err(
      InvalidData("timestamp must be a nonnegative decimal Int64 string"),
    )
  }
  if text.length() > 1 && text.has_prefix("0") {
    return Err(InvalidData("timestamp has a leading zero"))
  }
  for char in text.to_array() {
    if char < '0' || char > '9' {
      return Err(InvalidData("timestamp contains a nondecimal character"))
    }
  }
  Ok(@string.parse_int64(text[:])) catch {
    _ => Err(InvalidData("timestamp exceeds Int64"))
  }
}

///|
/// Timestamps are decimal strings, preserving every Int64 bit in JavaScript.
/// Unknown fields and duplicate keys are rejected to prevent silent typos.
pub fn Observation::from_json(
  text : String,
) -> Result[Observation, MonitorError] {
  let json = match read_json(text, 1048576) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let object = match json {
    Object(fields) if fields.length() == 2 => fields
    _ => return Err(InvalidData("observation requires exactly time and values"))
  }
  let time = match object.get("time") {
    Some(String(value)) =>
      match decimal_timestamp(value) {
        Err(e) => return Err(e)
        Ok(value) => value
      }
    _ => return Err(InvalidData("time must be a decimal string"))
  }
  let fields = match object.get("values") {
    Some(Object(fields)) => fields
    _ => return Err(InvalidData("values must be an object"))
  }
  let values : Map[String, Bool] = Map([])
  for key, value in fields {
    match value {
      True => values.set(key, true)
      False => values.set(key, false)
      _ => return Err(InvalidData("atom values must be Boolean"))
    }
  }
  Observation::new(time, values)
}

///|
pub fn Observation::to_json(self : Observation) -> String {
  let values : Map[String, Json] = Map([])
  for key, value in self.values {
    values.set(key, Json::boolean(value))
  }
  Json::object(
    Map([
      ("time", Json::string(self.time.to_string())),
      ("values", Json::object(values)),
    ]),
  ).stringify()
}

///|
/// Portable rule documents carry syntax rather than internal DAG node IDs.
/// Resource limits are supplied by the receiver, never trusted from the wire.
pub fn Plan::from_json(
  text : String,
  limits~ : Limits = Limits::defaults(),
) -> Result[Plan, MonitorError] {
  let json = match read_json(text, 1048576) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let object = match json {
    Object(fields) if fields.length() == 2 => fields
    _ => return Err(InvalidData("rule document requires version and rules"))
  }
  if object.get("version") != Some(Json::string("1")) {
    return Err(InvalidData("unsupported rule document version"))
  }
  let rules = match object.get("rules") {
    Some(Array(rules)) => rules
    _ => return Err(InvalidData("rules must be an array"))
  }
  if rules.length() > limits.nodes {
    return Err(ResourceLimit("rule count"))
  }
  let parsed : Array[(String, String)] = []
  for rule in rules {
    let fields = match rule {
      Object(fields) if fields.length() == 2 => fields
      _ => return Err(InvalidData("rule requires exactly name and formula"))
    }
    match (fields.get("name"), fields.get("formula")) {
      (Some(String(name)), Some(String(formula))) =>
        parsed.push((name, formula))
      _ => return Err(InvalidData("rule name and formula must be strings"))
    }
  }
  Plan::from_strings(parsed, limits~)
}

///|
pub fn Plan::to_json(self : Plan) -> String {
  let rules : Array[Json] = []
  for i in 0..<self.names.length() {
    rules.push(
      Json::object(
        Map([
          ("name", Json::string(self.names[i])),
          ("formula", Json::string(format_formula(self.formulas[i]))),
        ]),
      ),
    )
  }
  Json::object(
    Map([("version", Json::string("1")), ("rules", Json::array(rules))]),
  ).stringify()
}

///|
pub fn Decision::to_json(self : Decision) -> String {
  let verdicts : Map[String, Json] = Map([])
  for i in 0..<self.names.length() {
    verdicts.set(self.names[i], Json::boolean(self.values[i]))
  }
  Json::object(
    Map([
      ("position", Json::number(self.position.to_double())),
      ("time", Json::string(self.time.to_string())),
      ("verdicts", Json::object(verdicts)),
    ]),
  ).stringify()
}

///|
/// JSONL replay is transactional per record, like push. Earlier accepted records
/// remain committed when a later line fails. A trailing newline is permitted;
/// blank records are errors. The whole batch has a 16 MiB code-unit ceiling.
pub fn Monitor::replay_jsonl(
  self : Monitor,
  text : String,
) -> Result[Array[Decision], MonitorError] {
  if text.length() > 16777216 {
    return Err(ResourceLimit("JSONL batch length"))
  }
  let lines = text.split("\n").to_array()
  let decisions : Array[Decision] = []
  for i in 0..<lines.length() {
    if i == lines.length() - 1 && lines[i].is_empty() {
      break
    }
    let event = match Observation::from_json(lines[i].to_owned()) {
      Ok(value) => value
      Err(e) =>
        return Err(
          InvalidData("line " + (i + 1).to_string() + ": " + e.message()),
        )
    }
    match self.push(event) {
      Ok(value) => decisions.push(value)
      Err(e) =>
        return Err(
          InvalidData("line " + (i + 1).to_string() + ": " + e.message()),
        )
    }
  }
  Ok(decisions)
}
