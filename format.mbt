///|
/// Canonical syntax with precedence-aware parentheses. Validation bounds AST
/// traversal and ensures every emitted identifier is accepted by the parser.
pub fn Formula::format(
  self : Formula,
  limits~ : Limits = Limits::defaults(),
) -> Result[String, MonitorError] {
  match Plan::new([("format", self)], limits~) {
    Err(e) => Err(e)
    Ok(_) => {
      let text = format_formula(self)
      match parse(text, limits~) {
        Err(e) => Err(e)
        Ok(_) => Ok(text)
      }
    }
  }
}

///|
fn format_interval(window : Interval) -> String {
  "[" + window.lower.to_string() + "," + window.upper.to_string() + "]"
}

///|
fn format_formula(formula : Formula) -> String {
  render_formula(formula, 0)
}

///|
fn render_formula(formula : Formula, minimum : Int32) -> String {
  let (precedence, text) = match formula {
    Constant(true) => (6, "true")
    Constant(false) => (6, "false")
    Atom(name) => (6, name)
    Not(child) => (5, "!" + render_formula(child, 5))
    Previous(child) => (5, "previous " + render_formula(child, 5))
    Once(window, child) =>
      (5, "once" + format_interval(window) + " " + render_formula(child, 5))
    Historically(window, child) =>
      (
        5,
        "historically" +
        format_interval(window) +
        " " +
        render_formula(child, 5),
      )
    And(a, b) => (3, render_formula(a, 3) + " & " + render_formula(b, 4))
    Or(a, b) => (2, render_formula(a, 2) + " | " + render_formula(b, 3))
    Implies(a, b) => (1, render_formula(a, 2) + " -> " + render_formula(b, 1))
    Since(window, a, b) =>
      (
        4,
        render_formula(a, 4) +
        " since" +
        format_interval(window) +
        " " +
        render_formula(b, 5),
      )
  }
  if precedence < minimum {
    "(" + text + ")"
  } else {
    text
  }
}
