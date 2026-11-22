///|
fn change_evidence(
  original : @moon-mtl.Evidence,
  node~ : Int32 = original.node,
  kind~ : String = original.kind,
  value~ : Bool = original.value,
  position~ : Int32 = original.position,
  time~ : Int64 = original.time,
  lower~ : Int64? = original.lower_age,
  upper~ : Int64? = original.upper_age,
  witness~ : @moon-mtl.Witness? = original.witness,
  barrier~ : @moon-mtl.Witness? = original.barrier,
) -> @moon-mtl.Evidence {
  {
    node,
    kind,
    value,
    position,
    time,
    lower_age: lower,
    upper_age: upper,
    witness,
    barrier,
  }
}

///|
test "explanations choose sufficient Boolean branches" {
  let plan = @moon-mtl.Plan::from_strings([
    ("and", "p & q"),
    ("or", "p | q"),
    ("implies", "p -> q"),
    ("not", "!p"),
  ]).unwrap()
  for p in [false, true] {
    for q in [false, true] {
      let trace = [event(0L, p, q)]
      let monitor = @moon-mtl.Monitor::new(plan)
      let decision = monitor.push(trace[0]).unwrap()
      assert_true(plan.verify_decision(trace, decision).unwrap())
      for name in plan.rule_names() {
        let evidence = monitor.explain(name).unwrap()
        assert_true(plan.verify_evidence(trace, evidence).unwrap())
        let expected = match name {
          "and" => if p && q { 3 } else { 2 }
          "or" => if p || q { 2 } else { 3 }
          "implies" => if p && !q { 3 } else { 2 }
          _ => 2
        }
        assert_eq(evidence.length(), expected)
      }
    }
  }
}

///|
test "temporal evidence stops at historical nodes and carries valid witness" {
  let plan = @moon-mtl.Plan::from_strings([
    ("once", "once[1,5] (p & q)"),
    ("historical", "historically[1,5] p"),
    ("previous", "previous q"),
    ("since", "p since[1,5] q"),
  ]).unwrap()
  let trace = [
    event(0L, false, true),
    event(1L, true, true),
    event(3L, true, false),
  ]
  let monitor = @moon-mtl.Monitor::new(plan)
  for observation in trace {
    monitor.push(observation).unwrap() |> ignore
  }
  for name in plan.rule_names() {
    let evidence = monitor.explain(name).unwrap()
    assert_eq(evidence.length(), 1)
    assert_true(evidence[0].witness is Some(_))
    assert_true(plan.verify_evidence(trace, evidence).unwrap())
  }
  let once = monitor.explain("once").unwrap()[0]
  assert_true(once.value)
  assert_eq(once.witness.unwrap().position, 1)
  let historical = monitor.explain("historical").unwrap()[0]
  assert_true(!historical.value)
  assert_eq(historical.witness.unwrap().position, 0)
  let previous = monitor.explain("previous").unwrap()[0]
  assert_eq(previous.witness.unwrap().position, 1)
  assert_true(previous.lower_age is None)
  assert_true(previous.upper_age is None)
}

///|
test "evidence rejects changed identity verdict time bounds and duplicate nodes" {
  let plan = @moon-mtl.Plan::from_strings([("r", "once[1,4] p")]).unwrap()
  let trace = [event(0L, true, false), event(2L, false, false)]
  let monitor = @moon-mtl.Monitor::new(plan)
  for observation in trace {
    monitor.push(observation).unwrap() |> ignore
  }
  let original = monitor.explain("r").unwrap()[0]
  for
    changed in [
      change_evidence(original, node=-1),
      change_evidence(original, node=9999),
      change_evidence(original, kind="historically"),
      change_evidence(original, value=false),
      change_evidence(original, position=-1),
      change_evidence(original, position=2),
      change_evidence(original, time=3L),
      change_evidence(original, lower=None),
      change_evidence(original, lower=Some(0L)),
      change_evidence(original, upper=None),
      change_evidence(original, upper=Some(5L)),
      change_evidence(original, witness=None),
      change_evidence(original, witness=Some({ position: 1, time: 2L, })),
      change_evidence(original, witness=Some({ position: 0, time: 1L, })),
      change_evidence(original, witness=Some({ position: -1, time: 0L, })),
      change_evidence(original, witness=Some({ position: 2, time: 2L, })),
      change_evidence(original, barrier=Some({ position: 0, time: 0L, })),
    ] {
    assert_true(!plan.verify_evidence(trace, [changed]).unwrap())
  }
  assert_true(!plan.verify_evidence(trace, [original, original]).unwrap())
  assert_true(plan.verify_evidence(trace, []).unwrap())
  assert_true(
    plan.verify_evidence(trace, [original, original, original]) is Err(_),
  )
}

///|
test "Since witnesses cannot cross a false left barrier" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p since[0,8] q")]).unwrap()
  let trace = [
    event(0L, true, true),
    event(2L, false, false),
    event(4L, true, true),
    event(5L, true, false),
  ]
  let monitor = @moon-mtl.Monitor::new(plan)
  for observation in trace {
    monitor.push(observation).unwrap() |> ignore
  }
  let original = monitor.explain("r").unwrap()[0]
  assert_true(original.value)
  assert_eq(original.witness.unwrap().position, 2)
  assert_eq(original.barrier.unwrap().position, 1)
  assert_true(plan.verify_evidence(trace, [original]).unwrap())
  assert_true(
    !plan
    .verify_evidence(trace, [
      change_evidence(original, witness=Some({ position: 0, time: 0L, })),
    ])
    .unwrap(),
  )
  assert_true(
    !plan
    .verify_evidence(trace, [
      change_evidence(original, barrier=Some({ position: 0, time: 0L, })),
    ])
    .unwrap(),
  )
  assert_true(
    !plan
    .verify_evidence(trace, [
      change_evidence(original, barrier=Some({ position: 1, time: 1L, })),
    ])
    .unwrap(),
  )
  assert_true(
    !plan
    .verify_evidence(trace, [
      change_evidence(original, barrier=Some({ position: 4, time: 6L, })),
    ])
    .unwrap(),
  )
}

///|
test "negative existential and vacuous universal claims carry no witness" {
  let plan = @moon-mtl.Plan::from_strings([
    ("once", "once[2,3] p"),
    ("all", "historically[2,3] p"),
    ("since", "p since[2,3] q"),
    ("previous", "previous p"),
  ]).unwrap()
  let trace = [event(0L, true, true)]
  let monitor = @moon-mtl.Monitor::new(plan)
  monitor.push(trace[0]).unwrap() |> ignore
  for name in plan.rule_names() {
    let original = monitor.explain(name).unwrap()[0]
    assert_true(original.witness is None)
    assert_true(plan.verify_evidence(trace, [original]).unwrap())
    let changed = change_evidence(
      original,
      witness=Some({ position: 0, time: 0L, }),
    )
    assert_true(!plan.verify_evidence(trace, [changed]).unwrap())
  }
}

///|
test "decision verification detects a different trace plan and position" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p")]).unwrap()
  let decision = @moon-mtl.Monitor::new(plan)
    .push(event(1L, true, false))
    .unwrap()
  assert_true(plan.verify_decision([event(1L, true, false)], decision).unwrap())
  assert_true(
    !plan.verify_decision([event(1L, false, false)], decision).unwrap(),
  )
  assert_true(
    !plan.verify_decision([event(2L, true, false)], decision).unwrap(),
  )
  assert_true(plan.verify_decision([], decision) is Err(_))
  let renamed = @moon-mtl.Plan::from_strings([("other", "p")]).unwrap()
  assert_true(
    !renamed.verify_decision([event(1L, true, false)], decision).unwrap(),
  )
  let changed = @moon-mtl.Plan::from_strings([("r", "!p")]).unwrap()
  assert_true(
    !changed.verify_decision([event(1L, true, false)], decision).unwrap(),
  )
}

///|
test "evidence verifies custom compiler limits without reverting to defaults" {
  let limits = @moon-mtl.Limits::new(nodes=1024, depth=128).unwrap()
  let mut formula : @moon-mtl.Formula = Atom("p")
  for _ in 0..<80 {
    formula = Not(formula)
  }
  let plan = @moon-mtl.Plan::new([("deep", formula)], limits~).unwrap()
  let trace = [event(0L, true, false)]
  let monitor = @moon-mtl.Monitor::new(plan)
  let decision = monitor.push(trace[0]).unwrap()
  assert_true(plan.verify_decision(trace, decision).unwrap())
  assert_true(
    plan.verify_evidence(trace, monitor.explain("deep").unwrap()).unwrap(),
  )
}

///|
test "one reference can verify several decisions against its owned trace" {
  let plan = @moon-mtl.Plan::from_strings([("r", "previous p")]).unwrap()
  let trace = [event(0L, true, false), event(1L, false, false)]
  let reference = @moon-mtl.Reference::new(plan, trace).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  let first = monitor.push(trace[0]).unwrap()
  let second = monitor.push(trace[1]).unwrap()
  trace[0] = event(0L, false, false)
  assert_true(reference.verify(first).unwrap())
  assert_true(reference.verify(second).unwrap())
  assert_true(!plan.verify_decision(trace, second).unwrap())
}
