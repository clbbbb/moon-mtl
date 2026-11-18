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
