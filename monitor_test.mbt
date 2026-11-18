///|
test "shared graph interns repeated subformulas across rules" {
  let plan = @moon-mtl.Plan::from_strings([
    ("a", "once[0,5] p"),
    ("b", "once[0,5] p"),
    ("c", "q -> once[0,5] p"),
  ]).unwrap()
  assert_eq(plan.rule_count(), 3)
  assert_eq(plan.node_count(), 4)
  assert_eq(plan.atom_names(), ["p", "q"])
  assert_eq(plan.rule_names(), ["a", "b", "c"])
  let monitor = @moon-mtl.Monitor::new(plan)
  let result = monitor.push(event(0L, true, true)).unwrap()
  assert_eq(result.names(), ["a", "b", "c"])
  assert_eq(result.values(), [true, true, true])
  assert_true(result.all_true())
  assert_eq(result.value("absent"), None)
  assert_eq(result.position(), 0)
  assert_eq(result.timestamp(), 0L)
  assert_eq(monitor.stats().node_updates, 4L)
  assert_eq(monitor.stats().retained_candidates, 1)
}

///|
test "missing atoms and out of order events leave every live state unchanged" {
  let plan = @moon-mtl.Plan::from_strings([("rule", "previous p & once[0,5] q")]).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  assert_true(monitor.last_decision() is None)
  let first = monitor.push(event(1L, true, true)).unwrap()
  let before = monitor.stats()
  let incomplete = @moon-mtl.Observation::new(2L, Map([("p", false)])).unwrap()
  assert_true(monitor.push(incomplete) is Err(@moon-mtl.MissingAtom("q", 1)))
  assert_eq(monitor.stats().processed, before.processed)
  assert_eq(monitor.stats().retained_candidates, before.retained_candidates)
  assert_eq(monitor.last_decision().unwrap().values(), first.values())
  assert_true(
    monitor.push(event(1L, false, false)) is Err(@moon-mtl.InvalidTimestamp(1)),
  )
  assert_true(monitor.push(event(0L, false, false)) is Err(_))
  let retried = monitor.push(event(2L, false, true)).unwrap()
  assert_eq(retried.values(), [true])
  assert_eq(monitor.stats().processed, 2)
}

///|
test "candidate budget errors roll back expired heads barriers and previous values" {
  let limits = @moon-mtl.Limits::new(candidates=2).unwrap()
  let plan = @moon-mtl.Plan::from_strings(
    [("o", "once[0,10] p"), ("s", "p since[0,10] q"), ("v", "previous p")],
    limits~,
  ).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  ignore(monitor.push(event(0L, true, true)).unwrap())
  assert_eq(monitor.stats().retained_candidates, 2)
  assert_true(
    monitor.push(event(1L, true, true)) is Err(@moon-mtl.ResourceLimit(_)),
  )
  assert_eq(monitor.stats().processed, 1)
  assert_eq(monitor.stats().retained_candidates, 2)
  assert_eq(monitor.stats().peak_candidates, 2)
  assert_eq(monitor.push(event(1L, false, false)).unwrap().values(), [
    true, false, true,
  ])
  assert_eq(monitor.stats().retained_candidates, 1)
  assert_eq(monitor.push(event(20L, false, false)).unwrap().values(), [
    false, false, false,
  ])
  assert_eq(monitor.stats().retained_candidates, 0)
}

///|
test "global candidate capacity accounts for sharing but not separate windows" {
  let limits = @moon-mtl.Limits::new(candidates=1).unwrap()
  let shared = @moon-mtl.Plan::from_strings(
    [("a", "once[0,5] p"), ("b", "once[0,5] p")],
    limits~,
  ).unwrap()
  assert_true(
    @moon-mtl.Monitor::new(shared).push(event(0L, true, false)) is Ok(_),
  )
  let distinct = @moon-mtl.Plan::from_strings(
    [("a", "once[0,5] p"), ("b", "once[0,6] p")],
    limits~,
  ).unwrap()
  let monitor = @moon-mtl.Monitor::new(distinct)
  assert_true(
    monitor.push(event(0L, true, false)) is Err(@moon-mtl.ResourceLimit(_)),
  )
  assert_eq(monitor.stats().processed, 0)
  assert_eq(monitor.stats().retained_candidates, 0)
}

///|
test "event count is enforced before admitting more observations" {
  let limits = @moon-mtl.Limits::new(events=2).unwrap()
  let plan = @moon-mtl.Plan::from_strings([("r", "p")], limits~).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  ignore(monitor.push(event(0L, true, false)).unwrap())
  ignore(monitor.push(event(1L, false, false)).unwrap())
  assert_true(
    monitor.push(event(2L, true, false)) is Err(@moon-mtl.ResourceLimit(_)),
  )
  assert_eq(monitor.stats().processed, 2)
  assert_eq(monitor.stats().node_updates, 2L)
  assert_eq(monitor.last_decision().unwrap().values(), [false])
  assert_true(
    plan.validate_trace([
      event(0L, true, false),
      event(1L, true, false),
      event(2L, true, false),
    ])
    is Err(_),
  )
}

///|
test "plans observations and decisions cannot alias mutable caller arrays or maps" {
  let rules = [("r", @moon-mtl.Atom("p"))]
  let plan = @moon-mtl.Plan::new(rules).unwrap()
  rules[0] = ("other", @moon-mtl.Constant(false))
  let values = Map([("p", true)])
  let observation = @moon-mtl.Observation::new(0L, values).unwrap()
  values["p"] = false
  let a = @moon-mtl.Monitor::new(plan)
  let b = @moon-mtl.Monitor::new(plan)
  let decision = a.push(observation).unwrap()
  let names = decision.names()
  let booleans = decision.values()
  names[0] = "corrupt"
  booleans[0] = false
  let atoms = plan.atom_names()
  atoms[0] = "other"
  assert_eq(decision.names(), ["r"])
  assert_eq(decision.values(), [true])
  assert_eq(plan.atom_names(), ["p"])
  assert_eq(b.stats().processed, 0)
  assert_eq(b.push(event(0L, false, false)).unwrap().values(), [false])
  assert_eq(a.last_decision().unwrap().values(), [true])
}

///|
test "reference owns the trace array and validates whole input before evaluation" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p")]).unwrap()
  let trace = [event(0L, true, false)]
  let reference = @moon-mtl.Reference::new(plan, trace).unwrap()
  trace[0] = event(0L, false, false)
  trace.push(event(1L, false, false))
  assert_eq(reference.evaluate(0).unwrap().values(), [true])
  assert_true(reference.evaluate(1) is Err(_))
  assert_eq(reference.last_steps(), 1)
}

///|
test "compiler rejects invalid identifiers rules and formula shapes" {
  assert_true(@moon-mtl.Plan::new([]) is Err(_))
  assert_true(
    @moon-mtl.Plan::new([("r", @moon-mtl.Atom("p")), ("r", @moon-mtl.Atom("q"))])
    is Err(_),
  )
  for name in ["", "x y", "1x", "a-b"] {
    assert_true(
      @moon-mtl.Plan::new([(name, @moon-mtl.Constant(true))]) is Err(_),
    )
    assert_true(@moon-mtl.Plan::new([("r", @moon-mtl.Atom(name))]) is Err(_))
    assert_true(@moon-mtl.Observation::new(0L, Map([(name, true)])) is Err(_))
  }
  for name in ["true", "false", "once", "historically", "since", "previous"] {
    assert_true(@moon-mtl.Plan::new([("r", @moon-mtl.Atom(name))]) is Err(_))
  }
  let plan = @moon-mtl.Plan::from_strings([("r", "true")]).unwrap()
  assert_true(plan.formula(-1) is Err(_))
  assert_true(plan.formula(1) is Err(_))
  assert_true(
    @moon-mtl.Plan::new(
      [("r", @moon-mtl.Not(@moon-mtl.Not(@moon-mtl.Atom("p"))))],
      limits=@moon-mtl.Limits::new(depth=2).unwrap(),
    )
    is Err(_),
  )
}

///|
test "invalid resource settings are rejected without overflow" {
  for bound in [-1, 0, 2147483647] {
    assert_true(@moon-mtl.Limits::new(nodes=bound) is Err(_))
    assert_true(@moon-mtl.Limits::new(depth=bound) is Err(_))
    assert_true(@moon-mtl.Limits::new(candidates=bound) is Err(_))
    assert_true(@moon-mtl.Limits::new(events=bound) is Err(_))
  }
  let limits = @moon-mtl.Limits::new(
    nodes=4096,
    depth=128,
    candidates=1000000,
    events=1000000000,
  ).unwrap()
  assert_eq(limits.max_nodes(), 4096)
  assert_eq(limits.max_depth(), 128)
  assert_eq(limits.max_candidates(), 1000000)
  assert_eq(limits.max_events(), 1000000000)
}
