///|
test "physical candidate storage is bounded by live state plus compaction slack" {
  let plan = Plan::from_strings([
    ("a", "once[3,80] p"),
    ("b", "historically[0,100] q"),
    ("c", "p since[4,120] q"),
  ]).unwrap()
  let monitor = Monitor::new(plan)
  for i in 0..<2500 {
    let observation = Observation::new(
      i.to_int64(),
      Map([("p", i % 47 != 0), ("q", i % 11 == 0)]),
    ).unwrap()
    monitor.push(observation).unwrap() |> ignore
    let mut total_live = 0
    for id in 0..<monitor.queues.length() {
      let queue = monitor.queues[id]
      assert_true(queue.head >= 0)
      assert_true(queue.head <= queue.items.length())
      let live = queue.items.length() - queue.head
      total_live += live
      assert_true(queue.items.length() <= 2 * live + 64)
      if live == 0 {
        assert_eq(queue.head, 0)
        assert_eq(queue.items.length(), 0)
      }
      for j in queue.head..<queue.items.length() {
        let candidate = queue.items[j]
        assert_true(candidate.position <= i)
        assert_eq(candidate.position.to_int64(), candidate.time)
        if j > queue.head {
          assert_true(queue.items[j - 1].time < candidate.time)
          assert_true(queue.items[j - 1].position < candidate.position)
        }
        match plan.nodes[id] {
          AnyPast(window, _) | AllPast(window, _) | SincePast(window, _, _) =>
            assert_true(observation.time - candidate.time <= window.upper)
          _ => fail("non-temporal node retained a candidate")
        }
      }
    }
    assert_eq(total_live, monitor.stats().retained_candidates)
  }
}

///|
test "queue compaction preserves the active suffix and appends one candidate" {
  let queue = CandidateQueue::new()
  for i in 0..<100 {
    queue.commit(queue.head, Some({ position: i, time: i.to_int64(), }))
  }
  assert_eq(queue.items.length(), 100)
  queue.commit(49, None)
  assert_eq(queue.head, 49)
  assert_eq(queue.items.length(), 100)
  queue.commit(50, Some({ position: 100, time: 100L, }))
  assert_eq(queue.head, 0)
  assert_eq(queue.items.length(), 51)
  assert_eq(queue.items[0].position, 50)
  assert_eq(queue.items[50].position, 100)
  queue.commit(51, None)
  assert_eq(queue.head, 0)
  assert_eq(queue.items.length(), 0)
}

///|
test "decision verifier rejects malformed private field combinations" {
  let plan = Plan::from_strings([("r", "p")]).unwrap()
  let trace = [Observation::new(0L, Map([("p", true)])).unwrap()]
  let original = Monitor::new(plan).push(trace[0]).unwrap()
  let valid = Decision::{ position: 0, time: 0L, names: ["r"], values: [true], }
  assert_true(plan.verify_decision(trace, valid).unwrap())
  for
    decision in [
      Decision::{ position: 0, time: 0L, names: ["r"], values: [], },
      Decision::{ position: 0, time: 0L, names: ["r"], values: [true, false], },
      Decision::{ position: 0, time: 0L, names: [], values: [true], },
      Decision::{ position: 0, time: 0L, names: ["other"], values: [true], },
      Decision::{ position: 0, time: 1L, names: ["r"], values: [true], },
      Decision::{ position: 0, time: 0L, names: ["r"], values: [false], },
    ] {
    assert_true(!plan.verify_decision(trace, decision).unwrap())
  }
  let invalid = Decision::{
    position: -1,
    time: 0L,
    names: ["r"],
    values: [true],
  }
  assert_true(plan.verify_decision(trace, invalid) is Err(_))
  let invalid = Decision::{
    position: 1,
    time: 0L,
    names: ["r"],
    values: [true],
  }
  assert_true(plan.verify_decision(trace, invalid) is Err(_))
  assert_eq(original.values(), [true])
}

///|
test "interned child edges always point strictly backwards" {
  let plan = Plan::from_strings([
    ("a", "previous (once[1,9] p & historically[2,7] q)"),
    ("b", "(p -> q) since[2,9] (p | q)"),
    ("c", "once[1,9] p & once[1,9] p"),
  ]).unwrap()
  for id in 0..<plan.nodes.length() {
    let children = match plan.nodes[id] {
      Literal(_) | Input(_) => []
      Neg(a) | Prior(a) | AnyPast(_, a) | AllPast(_, a) => [a]
      Both(a, b) | Either(a, b) | Implication(a, b) | SincePast(_, a, b) =>
        [a, b]
    }
    for child in children {
      assert_true(child >= 0)
      assert_true(child < id)
    }
  }
  let formulas = plan.node_formulas()
  assert_eq(formulas.length(), plan.nodes.length())
  let record = Observation::new(0L, Map([("p", true), ("q", false)])).unwrap()
  let decision = Monitor::new(plan).push(record).unwrap()
  for i in 0..<plan.roots.length() {
    assert_eq(
      evaluate_reference(formulas[plan.roots[i]], [record], 0).unwrap(),
      decision.values[i],
    )
  }
}
