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
