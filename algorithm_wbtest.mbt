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

///|
test "rule preflight rejects oversized batches before parsing their text" {
  let limits = Limits::new(nodes=1).unwrap()
  assert_true(
    Plan::from_strings([("a", "invalid@"), ("b", "p")], limits~)
    is Err(ResourceLimit(_)),
  )
  assert_true(
    Plan::from_strings([("a", "invalid@"), ("a", "p")])
    is Err(SyntaxError(0, "invalid or duplicate rule name")),
  )
  assert_true(
    Plan::from_strings([("bad name", "invalid@")])
    is Err(SyntaxError(0, "invalid or duplicate rule name")),
  )
  assert_true(Plan::from_strings([]) is Err(ResourceLimit(_)))
}

///|
test "binary expiration agrees with linear lower bound for all frontier shapes" {
  let queue = CandidateQueue::new()
  for i in 0..<257 {
    queue.items.push({ position: i, time: (i * 3).to_int64(), })
  }
  for head in 0..<258 {
    for upper in [0L, 1L, 17L, 180L, 770L, 9223372036854775807L] {
      for time in [770L, 800L, 1000L, 9223372036854775807L] {
        let mut expected = head
        while expected < queue.items.length() &&
              time - queue.items[expected].time > upper {
          expected += 1
        }
        assert_eq(queue.first_live(head, time, upper), expected)
      }
    }
  }
  assert_eq(CandidateQueue::new().first_live(0, 0L, 0L), 0)
}

///|
test "temporal commit schedule contains each queue owner exactly once" {
  let plan = Plan::from_strings([
    ("a", "once[1,3] p | previous q"),
    ("b", "historically[2,4] q & once[1,3] p"),
    ("c", "p since[0,5] q"),
  ]).unwrap()
  assert_eq(plan.temporal_nodes.length(), 3)
  let mut previous = -1
  for id in plan.temporal_nodes {
    assert_true(id > previous)
    assert_true(
      plan.nodes[id] is AnyPast(_, _) ||
      plan.nodes[id] is AllPast(_, _) ||
      plan.nodes[id] is SincePast(_, _, _),
    )
    previous = id
  }
  assert_eq(
    Plan::from_strings([("pure", "previous p & !q")]).unwrap().temporal_nodes.length(),
    0,
  )
}

///|
test "value double buffering isolates failed pushes and previously returned decisions" {
  let plan = Plan::from_strings(
    [("prior", "previous p"), ("window", "once[0,2] p")],
    limits=Limits::new(candidates=1).unwrap(),
  ).unwrap()
  let monitor = Monitor::new(plan)
  let first = monitor
    .push(Observation::new(0L, Map([("p", true)])).unwrap())
    .unwrap()
  let committed = monitor.last_values.copy()
  for _ in 0..<5 {
    assert_true(
      monitor.push(Observation::new(1L, Map([("p", true)])).unwrap()) is Err(_),
    )
    assert_eq(monitor.last_values, committed)
    assert_eq(first.values(), [false, true])
  }
  let second = monitor
    .push(Observation::new(1L, Map([("p", false)])).unwrap())
    .unwrap()
  assert_eq(second.values(), [true, true])
  assert_eq(
    monitor
    .push(Observation::new(4L, Map([("p", false)])).unwrap())
    .unwrap()
    .values(),
    [false, false],
  )
  assert_eq(first.values(), [false, true])
  assert_eq(second.values(), [true, true])
}

///|
test "reused queue staging overwrites aborted additions before committing a retry" {
  let plan = Plan::from_strings(
    [("a", "once[0,2] p"), ("b", "once[0,2] q")],
    limits=Limits::new(candidates=1).unwrap(),
  ).unwrap()
  let monitor = Monitor::new(plan)
  let event = fn(t, p, q) {
    Observation::new(t, Map([("p", p), ("q", q)])).unwrap()
  }
  assert_eq(monitor.push(event(0L, true, false)).unwrap().values(), [
    true, false,
  ])
  assert_true(monitor.push(event(1L, true, true)) is Err(_))
  assert_eq(monitor.push(event(10L, false, true)).unwrap().values(), [
    false, true,
  ])
  assert_true(monitor.push(event(11L, false, true)) is Err(_))
  assert_eq(monitor.push(event(11L, false, false)).unwrap().values(), [
    false, true,
  ])
  assert_eq(monitor.stats().retained_candidates, 1)
  assert_eq(monitor.stats().processed, 3)
}
