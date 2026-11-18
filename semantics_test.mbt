///|
test "empty temporal windows have explicit existential and universal identities" {
  let trace = [event(10L, false, false)]
  let window = @moon-mtl.Interval::new(1L, 3L).unwrap()
  assert_false(
    @moon-mtl.evaluate_reference(
      @moon-mtl.Once(window, @moon-mtl.Atom("p")),
      trace,
      0,
    ).unwrap(),
  )
  assert_true(
    @moon-mtl.evaluate_reference(
      @moon-mtl.Historically(window, @moon-mtl.Atom("p")),
      trace,
      0,
    ).unwrap(),
  )
  assert_false(
    @moon-mtl.evaluate_reference(
      @moon-mtl.Since(window, @moon-mtl.Atom("p"), @moon-mtl.Atom("q")),
      trace,
      0,
    ).unwrap(),
  )
  assert_false(
    @moon-mtl.evaluate_reference(
      @moon-mtl.Previous(@moon-mtl.Constant(true)),
      trace,
      0,
    ).unwrap(),
  )
}

///|
test "pointwise semantics do not hold values across missing timestamps" {
  let plan = @moon-mtl.Plan::from_strings([
    ("some", "once[1,4] p"),
    ("all", "historically[1,4] p"),
    ("prev", "previous p"),
  ]).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  ignore(monitor.push(event(0L, true, false)).unwrap())
  let result = monitor.push(event(10L, false, false)).unwrap()
  assert_eq(result.value("some"), Some(false))
  assert_eq(result.value("all"), Some(true))
  assert_eq(result.value("prev"), Some(true))
}

///|
test "since does not require its left operand at the witness itself" {
  let plan = @moon-mtl.Plan::from_strings([("s", "p since[0,4] q")]).unwrap()
  let trace = [
    event(0L, false, true),
    event(2L, true, false),
    event(3L, false, false),
  ]
  let reference = @moon-mtl.Reference::new(plan, trace).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  for i in 0..<3 {
    let actual = monitor.push(trace[i]).unwrap()
    assert_eq(actual.values(), reference.evaluate(i).unwrap().values())
    assert_eq(actual.value("s"), Some(i != 2))
  }
}

///|
test "since barrier clears older witnesses but admits a simultaneous new witness" {
  let plan = @moon-mtl.Plan::from_strings([("s", "p since[0,5] q")]).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  assert_eq(monitor.push(event(0L, true, true)).unwrap().value("s"), Some(true))
  assert_eq(
    monitor.push(event(1L, false, false)).unwrap().value("s"),
    Some(false),
  )
  assert_eq(
    monitor.push(event(2L, true, false)).unwrap().value("s"),
    Some(false),
  )
  assert_eq(
    monitor.push(event(3L, false, true)).unwrap().value("s"),
    Some(true),
  )
  assert_eq(
    monitor.push(event(4L, true, false)).unwrap().value("s"),
    Some(true),
  )
}

///|
test "lower bound delays witnesses and upper bound expires them inclusively" {
  let plan = @moon-mtl.Plan::from_strings([
    ("s", "p since[2,4] q"),
    ("o", "once[2,4] q"),
  ]).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  let expected = [false, false, true, true, true, false]
  for i in 0..<6 {
    let decision = monitor.push(event(i.to_int64(), true, i == 0)).unwrap()
    assert_eq(decision.values(), [expected[i], expected[i]])
  }
}

///|
test "historically tracks false candidates rather than every observation" {
  let plan = @moon-mtl.Plan::from_strings([("h", "historically[0,2] p")]).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  let expected = [true, false, false, false, true]
  for i in 0..<5 {
    assert_eq(
      monitor.push(event(i.to_int64(), i != 1, false)).unwrap().values(),
      [expected[i]],
    )
  }
  assert_eq(monitor.stats().retained_candidates, 0)
  assert_eq(monitor.stats().peak_candidates, 1)
}

///|
test "reference requires all atoms even in inactive windows or Boolean branches" {
  let missing = @moon-mtl.Observation::new(0L, Map([])).unwrap()
  for rule in ["true | p", "false & p", "once[5,10] p", "previous p"] {
    assert_true(
      @moon-mtl.evaluate_reference(@moon-mtl.parse(rule).unwrap(), [missing], 0)
      is Err(@moon-mtl.MissingAtom("p", 0)),
    )
  }
}

///|
test "invalid timestamp sequences and positions are explicit errors" {
  let formula = @moon-mtl.Atom("p")
  for
    trace in [
      [event(1L, true, false), event(1L, false, false)],
      [event(5L, true, false), event(4L, false, false)],
    ] {
    assert_true(
      @moon-mtl.evaluate_reference(formula, trace, 0)
      is Err(@moon-mtl.InvalidTimestamp(1)),
    )
  }
  for position in [-1, 1, 2147483647] {
    assert_true(
      @moon-mtl.evaluate_reference(formula, [event(0L, true, false)], position)
      is Err(@moon-mtl.InvalidPosition(_)),
    )
  }
  assert_true(@moon-mtl.evaluate_reference(formula, [], 0) is Err(_))
  assert_true(@moon-mtl.Observation::new(-1L, Map([])) is Err(_))
  assert_true(@moon-mtl.Interval::new(-1L, 2L) is Err(_))
  assert_true(@moon-mtl.Interval::new(2L, 1L) is Err(_))
}

///|
test "timestamp subtraction handles the full nonnegative Int64 range" {
  let plan = @moon-mtl.Plan::from_strings([
    ("all", "once[0,9223372036854775807] q"),
    ("last", "once[0,0] q"),
    ("exact", "once[9223372036854775807,9223372036854775807] q"),
  ]).unwrap()
  let trace = [event(0L, true, true), event(9223372036854775807L, true, false)]
  let monitor = @moon-mtl.Monitor::new(plan)
  for observation in trace {
    ignore(monitor.push(observation).unwrap())
  }
  let final_result = monitor.last_decision().unwrap()
  assert_eq(final_result.values(), [true, false, true])
  assert_true(plan.verify_decision(trace, final_result).unwrap())
}

///|
test "reference fuel bounds deeply nested enumeration without changing semantics" {
  let formula = @moon-mtl.parse(
    "historically[0,20](once[0,20](p since[0,20] q))",
  ).unwrap()
  let trace : Array[@moon-mtl.Observation] = []
  for i in 0..<20 {
    trace.push(event(i.to_int64(), true, true))
  }
  assert_true(
    @moon-mtl.evaluate_reference(formula, trace, 19, steps=20)
    is Err(@moon-mtl.ResourceLimit(_)),
  )
  assert_true(
    @moon-mtl.evaluate_reference(formula, trace, 19, steps=1000000) is Ok(true),
  )
  for fuel in [0, -1, 100000001] {
    assert_true(
      @moon-mtl.evaluate_reference(formula, trace, 0, steps=fuel) is Err(_),
    )
  }
}
