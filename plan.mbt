///|
enum Node {
  Literal(Bool)
  Input(String)
  Neg(Int32)
  Both(Int32, Int32)
  Either(Int32, Int32)
  Implication(Int32, Int32)
  Prior(Int32)
  AnyPast(Interval, Int32)
  AllPast(Interval, Int32)
  SincePast(Interval, Int32, Int32)
}

///|
/// Immutable shared execution graph. Rule order is preserved; every child node
/// precedes its parents, so one event needs only one topological pass.
pub struct Plan {
  priv nodes : Array[Node]
  priv roots : Array[Int32]
  priv names : Array[String]
  priv formulas : Array[Formula]
  priv atoms : Array[String]
  priv limits : Limits
}

///|
priv struct Compiler {
  nodes : Array[Node]
  keys : Map[String, Int32]
  atoms : Array[String]
  atom_set : Map[String, Bool]
  limits : Limits
  mut visits : Int32
}

///|
fn reserved_atom(name : String) -> Bool {
  name == "true" ||
  name == "false" ||
  name == "previous" ||
  name == "once" ||
  name == "historically" ||
  name == "since"
}

///|
fn Compiler::intern(
  self : Compiler,
  key : String,
  node : Node,
) -> Result[Int32, MonitorError] {
  match self.keys.get(key) {
    Some(id) => Ok(id)
    None => {
      if self.nodes.length() >= self.limits.nodes {
        return Err(ResourceLimit("shared graph node budget"))
      }
      let id = self.nodes.length()
      self.keys[key] = id
      self.nodes.push(node)
      Ok(id)
    }
  }
}

///|
fn Compiler::visit(
  self : Compiler,
  formula : Formula,
  depth : Int32,
) -> Result[Int32, MonitorError] {
  self.visits += 1
  if depth > self.limits.depth || self.visits > self.limits.nodes * 16 {
    return Err(ResourceLimit("formula nesting or syntax traversal budget"))
  }
  match formula {
    Constant(value) => self.intern("constant:\{value}", Literal(value))
    Atom(name) => {
      if !valid_identifier(name) || reserved_atom(name) {
        return Err(SyntaxError(0, "invalid or reserved atom name"))
      }
      if self.atom_set.get(name) is None {
        self.atom_set[name] = true
        self.atoms.push(name)
      }
      self.intern("input:" + name, Input(name))
    }
    Not(child) | Previous(child) => {
      let id = match self.visit(child, depth + 1) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      if formula is Not(_) {
        self.intern("not:\{id}", Neg(id))
      } else {
        self.intern("previous:\{id}", Prior(id))
      }
    }
    And(left, right) | Or(left, right) | Implies(left, right) => {
      let a = match self.visit(left, depth + 1) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      let b = match self.visit(right, depth + 1) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      match formula {
        And(_, _) => self.intern("and:\{a}:\{b}", Both(a, b))
        Or(_, _) => self.intern("or:\{a}:\{b}", Either(a, b))
        _ => self.intern("implies:\{a}:\{b}", Implication(a, b))
      }
    }
    Once(window, child) | Historically(window, child) => {
      let id = match self.visit(child, depth + 1) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      if formula is Once(_, _) {
        self.intern(
          "once:\{window.lower}:\{window.upper}:\{id}",
          AnyPast(window, id),
        )
      } else {
        self.intern(
          "historically:\{window.lower}:\{window.upper}:\{id}",
          AllPast(window, id),
        )
      }
    }
    Since(window, left, right) => {
      let a = match self.visit(left, depth + 1) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      let b = match self.visit(right, depth + 1) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      self.intern(
        "since:\{window.lower}:\{window.upper}:\{a}:\{b}",
        SincePast(window, a, b),
      )
    }
  }
}

///|
pub fn Plan::new(
  rules : Array[(String, Formula)],
  limits~ : Limits = Limits::defaults(),
) -> Result[Plan, MonitorError] {
  if rules.length() == 0 || rules.length() > limits.nodes {
    return Err(ResourceLimit("rule count must be 1..max_nodes"))
  }
  let compiler = Compiler::{
    nodes: [],
    keys: Map([]),
    atoms: [],
    atom_set: Map([]),
    limits,
    visits: 0,
  }
  let roots : Array[Int32] = []
  let names : Array[String] = []
  let seen_names : Map[String, Bool] = Map([])
  let formulas : Array[Formula] = []
  for (name, formula) in rules {
    if !valid_identifier(name) || seen_names.get(name) is Some(_) {
      return Err(SyntaxError(0, "invalid or duplicate rule name"))
    }
    let id = match compiler.visit(formula, 1) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    roots.push(id)
    seen_names[name] = true
    names.push(name)
    formulas.push(formula)
  }
  Ok({
    nodes: compiler.nodes,
    atoms: compiler.atoms,
    roots,
    names,
    formulas,
    limits,
  })
}

///|
pub fn Plan::from_strings(
  rules : Array[(String, String)],
  limits~ : Limits = Limits::defaults(),
) -> Result[Plan, MonitorError] {
  let parsed : Array[(String, Formula)] = []
  for (name, text) in rules {
    let formula = match parse(text, limits~) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    parsed.push((name, formula))
  }
  Plan::new(parsed, limits~)
}

///|
pub fn Plan::node_count(self : Plan) -> Int32 {
  self.nodes.length()
}

///|
pub fn Plan::rule_count(self : Plan) -> Int32 {
  self.roots.length()
}

///|
pub fn Plan::atom_names(self : Plan) -> Array[String] {
  self.atoms.copy()
}

///|
pub fn Plan::rule_names(self : Plan) -> Array[String] {
  self.names.copy()
}

///|
pub fn Plan::formula(
  self : Plan,
  rule : Int32,
) -> Result[Formula, MonitorError] {
  if rule < 0 || rule >= self.formulas.length() {
    Err(InvalidPosition(rule))
  } else {
    Ok(self.formulas[rule])
  }
}

///|
/// Validate every required atom before evaluating any branch or time window.
fn Plan::validate_observation(
  self : Plan,
  event : Observation,
  position : Int32,
) -> Result[Unit, MonitorError] {
  for atom in self.atoms {
    if event.values.get(atom) is None {
      return Err(MissingAtom(atom, position))
    }
  }
  Ok(())
}

///|
pub fn Plan::validate_trace(
  self : Plan,
  trace : Array[Observation],
) -> Result[Unit, MonitorError] {
  if trace.length() > self.limits.events {
    return Err(ResourceLimit("trace event count"))
  }
  for i in 0..<trace.length() {
    if i > 0 && trace[i].time <= trace[i - 1].time {
      return Err(InvalidTimestamp(i))
    }
    match self.validate_observation(trace[i], i) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  Ok(())
}
