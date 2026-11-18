///|
struct Generator {
  mut state : Int32
}

///|
fn Generator::next(self : Generator, bound : Int32) -> Int32 {
  self.state = (self.state * 1664525 + 1013904223) & 0x7fffffff
  self.state % bound
}

///|
fn Generator::formula(self : Generator, depth : Int32) -> @moon-mtl.Formula {
  if depth == 0 {
    return match self.next(4) {
      0 => Constant(true)
      1 => Constant(false)
      2 => Atom("p")
      _ => Atom("q")
    }
  }
  let low = self.next(4).to_int64()
  let window = @moon-mtl.Interval::new(low, low + self.next(7).to_int64()).unwrap()
  match self.next(10) {
    0 => Atom("p")
    1 => Atom("q")
    2 => Not(self.formula(depth - 1))
    3 => And(self.formula(depth - 1), self.formula(depth - 1))
    4 => Or(self.formula(depth - 1), self.formula(depth - 1))
    5 => Implies(self.formula(depth - 1), self.formula(depth - 1))
    6 => Previous(self.formula(depth - 1))
    7 => Once(window, self.formula(depth - 1))
    8 => Historically(window, self.formula(depth - 1))
    _ => Since(window, self.formula(depth - 1), self.formula(depth - 1))
  }
}

///|
test "seeded irregular traces agree with independent recursive semantics" {
  let random = Generator::{ state: 20261118, }
  for case in 0..<240 {
    let formula = random.formula(3)
    let canonical = formula.format().unwrap()
    let reparsed = @moon-mtl.parse(canonical).unwrap()
    assert_eq(reparsed.format().unwrap(), canonical)
    let plan = @moon-mtl.Plan::new([
      ("generated", formula),
      ("roundtrip", reparsed),
    ]).unwrap()
    let trace : Array[@moon-mtl.Observation] = []
    let mut time = 0L
    for _ in 0..<24 {
      time += (1 + random.next(5)).to_int64()
      trace.push(event(time, random.next(7) < 3, random.next(11) < 4))
    }
    let monitor = @moon-mtl.Monitor::new(plan)
    let reference = @moon-mtl.Reference::new(plan, trace).unwrap()
    for i in 0..<trace.length() {
      let actual = monitor.push(trace[i]).unwrap()
      let expected = reference.evaluate(i).unwrap()
      assert_eq(
        actual.values(),
        expected.values(),
        msg="case " +
          case.to_string() +
          " at " +
          i.to_string() +
          ": " +
          canonical,
      )
      assert_true(
        plan
        .verify_evidence(trace, monitor.explain("generated").unwrap())
        .unwrap(),
      )
    }
  }
}

///|
test "all short Boolean traces exhaustively cover since boundaries" {
  for lower in 0..<4 {
    for upper in lower..<5 {
      let text = "p since[" +
        lower.to_string() +
        "," +
        upper.to_string() +
        "] q"
      let plan = @moon-mtl.Plan::from_strings([("since", text)]).unwrap()
      for bits in 0..<256 {
        let trace = Array::makei(4, i => {
          event(
            (i * 2).to_int64(),
            ((bits >> (i * 2)) & 1) == 1,
            ((bits >> (i * 2 + 1)) & 1) == 1,
          )
        })
        let reference = @moon-mtl.Reference::new(plan, trace).unwrap()
        let monitor = @moon-mtl.Monitor::new(plan)
        for i in 0..<4 {
          assert_eq(
            monitor.push(trace[i]).unwrap().values(),
            reference.evaluate(i).unwrap().values(),
          )
        }
      }
    }
  }
}

///|
test "candidate compaction and long expiration retain bounded active state" {
  let plan = @moon-mtl.Plan::from_strings([
    ("once", "once[2,70] p"),
    ("historical", "historically[3,90] q"),
    ("since", "p since[1,80] q"),
    ("nested", "once[2,7] historically[1,5] p"),
  ]).unwrap()
  let trace = Array::makei(1200, i => {
    event(i.to_int64(), i % 17 != 0, i % 5 == 0)
  })
  let monitor = @moon-mtl.Monitor::new(plan)
  let reference = @moon-mtl.Reference::new(plan, trace).unwrap()
  for i in 0..<trace.length() {
    let decision = monitor.push(trace[i]).unwrap()
    if i < 100 || i % 47 == 0 || i == trace.length() - 1 {
      assert_eq(decision.values(), reference.evaluate(i).unwrap().values())
    }
    assert_true(monitor.stats().retained_candidates <= 71 + 91 + 81 + 8 + 6)
  }
  assert_true(monitor.stats().peak_candidates > 32)
  assert_eq(monitor.stats().processed, 1200)
}

///|
test "timestamp translation preserves every bounded temporal verdict" {
  let plan = @moon-mtl.Plan::from_strings([
    ("a", "once[3,9] p"),
    ("b", "historically[0,7] (p | q)"),
    ("c", "previous (p since[2,15] q)"),
  ]).unwrap()
  let a = @moon-mtl.Monitor::new(plan)
  let b = @moon-mtl.Monitor::new(plan)
  for i in 0..<200 {
    let time = (i * i + i).to_int64()
    assert_eq(
      a.push(event(time, i % 3 == 0, i % 7 == 0)).unwrap().values(),
      b
      .push(event(time + 9007199254740993L, i % 3 == 0, i % 7 == 0))
      .unwrap()
      .values(),
    )
  }
}

///|
test "canonical syntax covers each constructor and rejects invalid atoms" {
  for
    text in [
      "true", "false", "p", "!p", "p & q", "p | q", "p -> q", "previous p", "once[0,1] p",
      "historically[0,1] p", "p since[0,1] q",
    ] {
    let formatted = @moon-mtl.parse(text).unwrap().format().unwrap()
    assert_eq(@moon-mtl.parse(formatted).unwrap().format().unwrap(), formatted)
  }
  assert_true(@moon-mtl.Formula::Atom("true").format() is Err(_))
  assert_true(@moon-mtl.Formula::Atom("bad name").format() is Err(_))
}
