///|
test "permuting rule order preserves named results and evidence validity" {
  let rules = [
    ("a", "once[1,9] (p & q)"),
    ("b", "historically[2,8] (p | q)"),
    ("c", "p since[1,7] previous q"),
    ("d", "previous (p -> once[0,3] q)"),
  ]
  let first = @moon-mtl.Plan::from_strings(rules).unwrap()
  let second = @moon-mtl.Plan::from_strings([
    rules[3],
    rules[1],
    rules[0],
    rules[2],
  ]).unwrap()
  let a = @moon-mtl.Monitor::new(first)
  let b = @moon-mtl.Monitor::new(second)
  let trace = Array::makei(120, i => {
    event((i * 2 + i / 5).to_int64(), i % 7 != 0, i % 11 == 0)
  })
  assert_eq(first.node_count(), second.node_count())
  for record in trace {
    let left = a.push(record).unwrap()
    let right = b.push(record).unwrap()
    for (name, _) in rules {
      assert_eq(left.value(name), right.value(name))
      assert_true(
        first.verify_evidence(trace, a.explain(name).unwrap()).unwrap(),
      )
      assert_true(
        second.verify_evidence(trace, b.explain(name).unwrap()).unwrap(),
      )
    }
  }
}

///|
test "constant-only formulas require no fabricated atom observations" {
  let plan = @moon-mtl.Plan::from_strings([
    ("true", "true"),
    ("false", "false"),
    ("recent", "once[1,4] true"),
    ("history", "historically[1,4] false"),
    ("previous", "previous true"),
  ]).unwrap()
  assert_eq(plan.atom_names(), [])
  let monitor = @moon-mtl.Monitor::new(plan)
  let first = @moon-mtl.Observation::new(0L, Map([])).unwrap()
  let second = @moon-mtl.Observation::new(2L, Map([])).unwrap()
  let third = @moon-mtl.Observation::new(10L, Map([])).unwrap()
  assert_eq(monitor.push(first).unwrap().values(), [
    true, false, false, true, false,
  ])
  assert_eq(monitor.push(second).unwrap().values(), [
    true, false, true, false, true,
  ])
  assert_eq(monitor.push(third).unwrap().values(), [
    true, false, false, true, true,
  ])
  assert_eq(monitor.stats().processed, 3)
}

///|
test "unknown rule names are never interpreted as false verdicts" {
  let plan = @moon-mtl.Plan::from_strings([("known", "true")]).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  let decision = monitor
    .push(@moon-mtl.Observation::new(0L, Map([])).unwrap())
    .unwrap()
  assert_eq(decision.value("known"), Some(true))
  assert_eq(decision.value("missing"), None)
  assert_true(monitor.explain("missing") is Err(_))
}
