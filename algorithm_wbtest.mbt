///|
test "atom collection deduplicates in first occurrence order" {
  let rules = Array::makei(200, i => {
    ("r" + i.to_string(), And(Atom("p" + i.to_string()), Atom("common")))
  })
  let plan = Plan::new(rules, limits=Limits::new(nodes=1024).unwrap()).unwrap()
  assert_eq(plan.atoms.length(), 201)
  assert_eq(plan.atoms[0], "p0")
  assert_eq(plan.atoms[1], "common")
  assert_eq(plan.atoms[200], "p199")
}

///|
test "large rule sets preserve order and reject a late duplicate" {
  let rules = Array::makei(400, i => ("rule" + i.to_string(), Constant(true)))
  let plan = Plan::new(rules).unwrap()
  assert_eq(plan.rule_count(), 400)
  assert_eq(plan.node_count(), 1)
  assert_eq(plan.names[399], "rule399")
  rules[399] = rules[0]
  assert_true(Plan::new(rules) is Err(SyntaxError(_, _)))
}
