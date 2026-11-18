///|
test "temporal duality and Since existential reduction hold on irregular traces" {
  let random = Generator::{ state: 7319, }
  for _ in 0..<80 {
    let low = random.next(6).to_int64()
    let high = low + random.next(12).to_int64()
    let interval = @moon-mtl.Interval::new(low, high).unwrap()
    let child = random.formula(2)
    let plan = @moon-mtl.Plan::new([
      ("once", Once(interval, child)),
      ("since", Since(interval, Constant(true), child)),
      ("historical", Historically(interval, child)),
      ("dual", Not(Once(interval, Not(child)))),
      ("not_once", Not(Once(interval, child))),
      ("dual_once", Historically(interval, Not(child))),
    ]).unwrap()
    let monitor = @moon-mtl.Monitor::new(plan)
    let mut time = 0L
    for _ in 0..<70 {
      time += (random.next(5) + 1).to_int64()
      let values = monitor
        .push(event(time, random.next(13) < 5, random.next(17) < 7))
        .unwrap()
        .values()
      assert_eq(values[0], values[1])
      assert_eq(values[2], values[3])
      assert_eq(values[4], values[5])
    }
  }
}

///|
test "Previous distributes over Boolean conjunction and disjunction" {
  let plan = @moon-mtl.Plan::from_strings([
    ("and_left", "previous (p & q)"),
    ("and_right", "previous p & previous q"),
    ("or_left", "previous (p | q)"),
    ("or_right", "previous p | previous q"),
    ("neg_left", "previous !p"),
    ("neg_right", "!previous p"),
  ]).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  for i in 0..<100 {
    let values = monitor
      .push(event((i * 13).to_int64(), i % 3 != 0, i % 7 == 0))
      .unwrap()
      .values()
    assert_eq(values[0], values[1])
    assert_eq(values[2], values[3])
    // Strong Previous is false initially, so negation commutes only afterwards.
    if i > 0 {
      assert_eq(values[4], values[5])
    } else {
      assert_eq(values[4], false)
      assert_eq(values[5], true)
    }
  }
}

///|
test "zero-age temporal operators collapse to current sample" {
  let plan = @moon-mtl.Plan::from_strings([
    ("once", "once[0,0] p"),
    ("all", "historically[0,0] p"),
    ("since", "q since[0,0] p"),
  ]).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  for i in 0..<128 {
    let p = i % 3 == 0
    let values = monitor
      .push(event((i * i).to_int64(), p, i % 7 == 0))
      .unwrap()
      .values()
    assert_eq(values, [p, p, p])
  }
}

///|
test "enlarging a window is monotone for Once and antitone for Historically" {
  let plan = @moon-mtl.Plan::from_strings([
    ("small_once", "once[3,5] p"),
    ("large_once", "once[1,12] p"),
    ("small_all", "historically[3,5] p"),
    ("large_all", "historically[1,12] p"),
    ("small_since", "q since[3,5] p"),
    ("large_since", "q since[1,12] p"),
  ]).unwrap()
  let random = Generator::{ state: 671, }
  let monitor = @moon-mtl.Monitor::new(plan)
  let mut time = 0L
  for _ in 0..<400 {
    time += (1 + random.next(7)).to_int64()
    let values = monitor
      .push(event(time, random.next(10) < 4, random.next(10) < 7))
      .unwrap()
      .values()
    assert_true(!values[0] || values[1])
    assert_true(!values[3] || values[2])
    assert_true(!values[4] || values[5])
  }
}

///|
test "adding unrelated atoms and unrelated rules preserves existing results" {
  let rules = [("r", "p since[2,11] (previous q | p)")]
  let original = @moon-mtl.Monitor::new(
    @moon-mtl.Plan::from_strings(rules).unwrap(),
  )
  let extended = @moon-mtl.Monitor::new(
    @moon-mtl.Plan::from_strings([
      rules[0],
      ("unrelated", "historically[0,8] r"),
    ]).unwrap(),
  )
  for i in 0..<120 {
    let base = event(i.to_int64(), i % 5 != 0, i % 9 == 0)
    let richer = @moon-mtl.Observation::new(
      i.to_int64(),
      Map([
        ("p", i % 5 != 0),
        ("q", i % 9 == 0),
        ("r", i % 2 == 0),
        ("unused", true),
      ]),
    ).unwrap()
    assert_eq(
      original.push(base).unwrap().values()[0],
      extended.push(richer).unwrap().values()[0],
    )
  }
}

///|
test "prefix causality rejects accidental future dependence" {
  let plan = @moon-mtl.Plan::from_strings([
    ("r", "historically[0,6] (p -> once[1,8] q)"),
    ("s", "previous (p since[2,9] q)"),
  ]).unwrap()
  let trace = Array::makei(30, i => {
    event((i * 3).to_int64(), i % 3 == 0, i % 5 == 0)
  })
  let full = @moon-mtl.Reference::new(plan, trace).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  for i in 0..<trace.length() {
    let prefix = trace[:i + 1].to_owned()
    let short = @moon-mtl.Reference::new(plan, prefix).unwrap()
    let online = monitor.push(trace[i]).unwrap()
    assert_eq(
      short.evaluate(i).unwrap().values(),
      full.evaluate(i).unwrap().values(),
    )
    assert_eq(online.values(), full.evaluate(i).unwrap().values())
  }
}

///|
test "shared Boolean subexpressions are evaluated once per event" {
  let sub : @moon-mtl.Formula = And(Atom("p"), Atom("q"))
  let plan = @moon-mtl.Plan::new([
    ("and", And(sub, sub)),
    ("or", Or(sub, sub)),
    ("implies", Implies(sub, sub)),
  ]).unwrap()
  assert_eq(plan.node_count(), 6)
  let monitor = @moon-mtl.Monitor::new(plan)
  for i in 0..<100 {
    let p = i % 2 == 0
    let q = i % 3 == 0
    assert_eq(monitor.push(event(i.to_int64(), p, q)).unwrap().values(), [
      p && q,
      p && q,
      true,
    ])
  }
  assert_eq(monitor.stats().node_updates, 600L)
  assert_eq(monitor.stats().retained_candidates, 0)
}
