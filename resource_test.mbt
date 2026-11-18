///|
test "every rejected candidate update preserves the full future trajectory" {
  let limits = @moon-mtl.Limits::new(candidates=3).unwrap()
  let plan = @moon-mtl.Plan::from_strings(
    [
      ("a", "once[1,3] p"),
      ("b", "historically[1,3] q"),
      ("c", "previous (p since[1,3] q)"),
    ],
    limits~,
  ).unwrap()
  let tested = @moon-mtl.Monitor::new(plan)
  let control = @moon-mtl.Monitor::new(plan)
  let accepted : Array[@moon-mtl.Observation] = []
  let random = Generator::{ state: 12517, }
  let mut time = 0L
  let mut failures = 0
  for _ in 0..<300 {
    time += (random.next(3) + 1).to_int64()
    let record = event(time, random.next(7) < 5, random.next(11) < 6)
    let before = tested.stats()
    match tested.push(record) {
      Err(_) => {
        failures += 1
        assert_eq(tested.stats().processed, before.processed)
        assert_eq(
          tested.stats().retained_candidates,
          before.retained_candidates,
        )
        assert_eq(tested.stats().peak_candidates, before.peak_candidates)
        assert_eq(tested.stats().node_updates, before.node_updates)
        match (tested.last_decision(), control.last_decision()) {
          (Some(a), Some(b)) => assert_eq(a.to_json(), b.to_json())
          (None, None) => ()
          _ => fail("rollback changed last decision")
        }
      }
      Ok(actual) => {
        accepted.push(record)
        let expected = control.push(record).unwrap()
        assert_eq(actual.to_json(), expected.to_json())
        let reference = @moon-mtl.Reference::new(plan, accepted).unwrap()
        assert_eq(
          actual.values(),
          reference.evaluate(accepted.length() - 1).unwrap().values(),
        )
      }
    }
  }
  assert_true(failures > 0)
  assert_true(accepted.length() > 0)
}

///|
test "expiring candidates frees capacity before adding a current candidate" {
  let limits = @moon-mtl.Limits::new(candidates=1).unwrap()
  let plan = @moon-mtl.Plan::from_strings([("r", "once[0,2] p")], limits~).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  assert_eq(monitor.push(event(0L, true, false)).unwrap().values(), [true])
  assert_true(monitor.push(event(2L, true, false)) is Err(_))
  assert_eq(monitor.stats().processed, 1)
  assert_eq(monitor.push(event(3L, true, false)).unwrap().values(), [true])
  assert_eq(monitor.stats().retained_candidates, 1)
  assert_eq(monitor.stats().peak_candidates, 1)
  assert_eq(monitor.push(event(6L, false, false)).unwrap().values(), [false])
  assert_eq(monitor.stats().retained_candidates, 0)
}

///|
test "Since clearing can free a budget even at the same event as insertion" {
  let limits = @moon-mtl.Limits::new(candidates=1).unwrap()
  let plan = @moon-mtl.Plan::from_strings([("r", "p since[0,100] q")], limits~).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  monitor.push(event(0L, true, true)).unwrap() |> ignore
  assert_true(monitor.push(event(1L, true, true)) is Err(_))
  assert_eq(monitor.push(event(1L, false, true)).unwrap().values(), [true])
  assert_eq(monitor.stats().retained_candidates, 1)
  let evidence = monitor.explain("r").unwrap()[0]
  assert_eq(evidence.witness.unwrap().position, 1)
  assert_eq(evidence.barrier.unwrap().position, 1)
  assert_eq(monitor.push(event(2L, false, false)).unwrap().values(), [false])
  assert_eq(monitor.stats().retained_candidates, 0)
}

///|
test "global state budget counts ineligible future candidates" {
  let limits = @moon-mtl.Limits::new(candidates=2).unwrap()
  let plan = @moon-mtl.Plan::from_strings([("r", "once[100,200] p")], limits~).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  assert_eq(monitor.push(event(0L, true, false)).unwrap().values(), [false])
  assert_eq(monitor.push(event(1L, true, false)).unwrap().values(), [false])
  assert_eq(monitor.stats().retained_candidates, 2)
  assert_true(monitor.push(event(2L, true, false)) is Err(_))
  assert_eq(monitor.push(event(100L, false, false)).unwrap().values(), [true])
  assert_eq(monitor.stats().retained_candidates, 2)
  assert_eq(monitor.push(event(202L, true, false)).unwrap().values(), [false])
  assert_eq(monitor.stats().retained_candidates, 1)
}

///|
test "reference work budget resets after a failed evaluation" {
  let plan = @moon-mtl.Plan::from_strings([
    ("r", "once[0,100] (p since[0,100] q)"),
  ]).unwrap()
  let trace = Array::makei(15, i => event(i.to_int64(), true, i % 3 == 0))
  let reference = @moon-mtl.Reference::new(plan, trace, steps=40).unwrap()
  assert_true(reference.evaluate(14) is Err(_))
  assert_eq(reference.last_steps(), 40)
  assert_true(reference.evaluate(0) is Ok(_))
  assert_true(reference.last_steps() < 40)
  assert_true(reference.evaluate(14) is Err(_))
  assert_eq(reference.last_steps(), 40)
  assert_true(@moon-mtl.Reference::new(plan, trace, steps=0) is Err(_))
  assert_true(@moon-mtl.Reference::new(plan, trace, steps=100000001) is Err(_))
}

///|
test "compiler protects against exponential shared AST syntax expansion" {
  let mut formula : @moon-mtl.Formula = Atom("p")
  for _ in 0..<15 {
    formula = And(formula, formula)
  }
  let limits = @moon-mtl.Limits::new(nodes=32, depth=32).unwrap()
  assert_true(@moon-mtl.Plan::new([("r", formula)], limits~) is Err(_))
}
