///|
test "canonical printer preserves binary associativity and required parentheses" {
  for
    (source, expected) in [
      ("(p)", "p"),
      ("! (p)", "!p"),
      ("p & (q & p)", "p & (q & p)"),
      ("(p & q) & p", "p & q & p"),
      ("p | (q | p)", "p | (q | p)"),
      ("(p | q) | p", "p | q | p"),
      ("(p -> q) -> p", "(p -> q) -> p"),
      ("p -> (q -> p)", "p -> q -> p"),
      ("!(p | q)", "!(p | q)"),
      ("previous (p | q)", "previous (p | q)"),
      ("once[1,3] (p & q)", "once[1,3] (p & q)"),
      ("historically[0,2] (p -> q)", "historically[0,2] (p -> q)"),
      ("(p since[0,2] q) since[1,3] p", "p since[0,2] q since[1,3] p"),
      ("p since[0,2] (q since[1,3] p)", "p since[0,2] (q since[1,3] p)"),
      ("(p | q) & p", "(p | q) & p"),
      ("p | (q & p)", "p | q & p"),
      ("(p & q) since[1,2] p", "(p & q) since[1,2] p"),
      ("p & (q since[1,2] p)", "p & q since[1,2] p"),
    ] {
    let original = @moon-mtl.parse(source).unwrap()
    let formatted = original.format().unwrap()
    assert_eq(formatted, expected)
    let restored = @moon-mtl.parse(formatted).unwrap()
    assert_eq(restored.format().unwrap(), expected)
    let a = @moon-mtl.Plan::new([("r", original)]).unwrap()
    let b = @moon-mtl.Plan::new([("r", restored)]).unwrap()
    assert_eq(a.node_count(), b.node_count())
  }
}

///|
test "deep unary formatting does not double the parser recursion requirement" {
  let limits = @moon-mtl.Limits::new(nodes=128, depth=128).unwrap()
  let mut formula : @moon-mtl.Formula = Atom("p")
  for _ in 0..<80 {
    formula = Not(formula)
  }
  let text = formula.format(limits~).unwrap()
  assert_eq(text, "!".repeat(80) + "p")
  let restored = @moon-mtl.parse(text, limits~).unwrap()
  let plan = @moon-mtl.Plan::new([("r", restored)], limits~).unwrap()
  assert_eq(
    @moon-mtl.Monitor::new(plan).push(event(0L, true, false)).unwrap().values(),
    [true],
  )
}

///|
test "formatter rejects ASTs whose expanded syntax exceeds the receiver budget" {
  let limits = @moon-mtl.Limits::new(nodes=16, depth=16).unwrap()
  let mut formula : @moon-mtl.Formula = Atom("p")
  for _ in 0..<5 {
    formula = And(formula, formula)
  }
  assert_true(@moon-mtl.Plan::new([("r", formula)], limits~) is Ok(_))
  assert_true(formula.format(limits~) is Err(_))
}

///|
test "all Boolean precedence triples retain semantics after formatting" {
  let operators = [" & ", " | ", " -> "]
  for first in operators {
    for second in operators {
      for pattern in 0..<3 {
        let text = match pattern {
          0 => "p" + first + "q" + second + "p"
          1 => "(p" + first + "q)" + second + "p"
          _ => "p" + first + "(q" + second + "p)"
        }
        let original = @moon-mtl.parse(text).unwrap()
        let canonical = original.format().unwrap()
        let restored = @moon-mtl.parse(canonical).unwrap()
        for p in [false, true] {
          for q in [false, true] {
            let trace = [event(0L, p, q)]
            assert_eq(
              @moon-mtl.evaluate_reference(original, trace, 0).unwrap(),
              @moon-mtl.evaluate_reference(restored, trace, 0).unwrap(),
            )
          }
        }
      }
    }
  }
}
