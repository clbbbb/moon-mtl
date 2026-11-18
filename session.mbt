///|
/// Chunked JSONL ingestion. A session retains only the unfinished record and
/// monitor state. Failures seal the session: accepted prefixes cannot be
/// accidentally replayed by retrying the same chunk.
pub struct JsonlSession {
  priv monitor : Monitor
  priv mut pending : String
  priv mut records : Int32
  priv mut closed : Bool
  priv mut failure : MonitorError?
}

///|
pub fn JsonlSession::new(plan : Plan) -> JsonlSession {
  {
    monitor: Monitor::new(plan),
    pending: "",
    records: 0,
    closed: false,
    failure: None,
  }
}

///|
pub fn JsonlSession::stats(self : JsonlSession) -> MonitorStats {
  self.monitor.stats()
}

///|
pub fn JsonlSession::buffered_units(self : JsonlSession) -> Int32 {
  self.pending.length()
}

///|
pub fn JsonlSession::error(self : JsonlSession) -> MonitorError? {
  self.failure
}

///|
pub fn JsonlSession::is_finished(self : JsonlSession) -> Bool {
  self.closed && self.failure is None
}

///|
fn JsonlSession::reject(
  self : JsonlSession,
  error : MonitorError,
) -> MonitorError {
  let error = InvalidData(
    "line " + (self.records + 1).to_string() + ": " + error.message(),
  )
  self.failure = Some(error)
  self.closed = true
  self.pending = ""
  error
}

///|
fn JsonlSession::record(
  self : JsonlSession,
  text : String,
) -> Result[Decision, MonitorError] {
  let observation = match Observation::from_json(text) {
    Err(e) => return Err(self.reject(e))
    Ok(value) => value
  }
  match self.monitor.push(observation) {
    Err(e) => Err(self.reject(e))
    Ok(value) => {
      self.records += 1
      Ok(value)
    }
  }
}

///|
/// Each chunk and unfinished record is limited to 1 MiB UTF-16 code units.
/// Returned decisions cover completed lines only. On error, inspect stats or
/// last_decision for the accepted prefix; the Result does not carry that prefix.
pub fn JsonlSession::feed(
  self : JsonlSession,
  chunk : String,
) -> Result[Array[Decision], MonitorError] {
  if self.closed {
    return Err(self.failure.unwrap_or(InvalidData("JSONL session is finished")))
  }
  if chunk.length() > 1048576 {
    return Err(self.reject(ResourceLimit("JSONL chunk length")))
  }
  let joined = self.pending + chunk
  self.pending = ""
  let lines = joined.split("\n").to_array()
  let decisions : Array[Decision] = []
  for i in 0..<(lines.length() - 1) {
    match self.record(lines[i].to_owned()) {
      Err(e) => return Err(e)
      Ok(value) => decisions.push(value)
    }
  }
  let tail = lines[lines.length() - 1].to_owned()
  if tail.length() > 1048576 {
    return Err(self.reject(ResourceLimit("JSONL unfinished record length")))
  }
  self.pending = tail
  Ok(decisions)
}

///|
/// Finish an optional non-newline-terminated last record. Calling finish twice
/// succeeds with no extra decisions, while feed after finish is always rejected.
pub fn JsonlSession::finish(
  self : JsonlSession,
) -> Result[Array[Decision], MonitorError] {
  if self.failure is Some(error) {
    return Err(error)
  }
  if self.closed {
    return Ok([])
  }
  let decisions : Array[Decision] = []
  if !self.pending.is_empty() {
    let tail = self.pending
    self.pending = ""
    match self.record(tail) {
      Err(e) => return Err(e)
      Ok(value) => decisions.push(value)
    }
  }
  self.closed = true
  Ok(decisions)
}

///|
pub fn JsonlSession::last_decision(self : JsonlSession) -> Decision? {
  self.monitor.last_decision()
}

///|
pub fn JsonlSession::explain(
  self : JsonlSession,
  name : String,
) -> Result[Array[Evidence], MonitorError] {
  self.monitor.explain(name)
}
