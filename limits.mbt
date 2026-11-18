///|
/// Explicit ceilings bound parser, compiler, reference and live monitor work.
pub struct Limits {
  priv nodes : Int32
  priv depth : Int32
  priv candidates : Int32
  priv events : Int32
}

///|
pub fn Limits::new(
  nodes~ : Int32 = 512,
  depth~ : Int32 = 64,
  candidates~ : Int32 = 65536,
  events~ : Int32 = 1000000,
) -> Result[Limits, MonitorError] {
  if nodes < 1 ||
    nodes > 4096 ||
    depth < 1 ||
    depth > 128 ||
    candidates < 1 ||
    candidates > 1000000 ||
    events < 1 ||
    events > 1000000000 {
    return Err(
      ResourceLimit(
        "invalid limits: nodes<=4096, depth<=128, candidates<=1000000, events<=1000000000",
      ),
    )
  }
  Ok({ nodes, depth, candidates, events, })
}

///|
pub fn Limits::defaults() -> Limits {
  Limits::new().unwrap()
}

///|
pub fn Limits::max_nodes(self : Limits) -> Int32 {
  self.nodes
}

///|
pub fn Limits::max_depth(self : Limits) -> Int32 {
  self.depth
}

///|
pub fn Limits::max_candidates(self : Limits) -> Int32 {
  self.candidates
}

///|
pub fn Limits::max_events(self : Limits) -> Int32 {
  self.events
}

///|
fn valid_identifier(name : String) -> Bool {
  if name.length() == 0 || name.length() > 128 {
    return false
  }
  let chars = name.to_array()
  for i in 0..<chars.length() {
    let c = chars[i]
    let letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
    if !letter && !(i > 0 && ((c >= '0' && c <= '9') || c == '.')) {
      return false
    }
  }
  true
}

///|
pub fn MonitorError::message(self : MonitorError) -> String {
  match self {
    InvalidData(reason) => "invalid data: " + reason
    InvalidInterval => "interval requires 0 <= lower <= upper"
    InvalidTimestamp(i) =>
      "timestamps must be nonnegative and strictly increasing at observation \{i}"
    MissingAtom(name, i) => "missing atom \{name} at observation \{i}"
    InvalidPosition(i) => "invalid observation position \{i}"
    ResourceLimit(reason) => "resource limit: " + reason
    SyntaxError(position, reason) =>
      "syntax error at character \{position}: " + reason
  }
}
