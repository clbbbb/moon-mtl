///|
test "transported decisions can be independently checked against input records" {
  let plan = @moon-mtl.Plan::from_strings([
    ("recent", "once[1,5] p"),
    ("prior", "previous q"),
  ]).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  let trace = [
    event(0L, true, false),
    event(2L, false, true),
    event(7L, false, false),
  ]
  for observation in trace {
    let decision = monitor.push(observation).unwrap()
    let restored = plan.decision_from_json(decision.to_json()).unwrap()
    assert_eq(restored.names(), decision.names())
    assert_eq(restored.values(), decision.values())
    assert_eq(restored.position(), decision.position())
    assert_eq(restored.timestamp(), decision.timestamp())
    assert_true(plan.verify_decision(trace, restored).unwrap())
  }
}

///|
test "decision map order does not change declared rule order" {
  let plan = @moon-mtl.Plan::from_strings([("a", "p"), ("b", "q")]).unwrap()
  let first = plan
    .decision_from_json(
      "{\"position\":0,\"time\":\"0\",\"verdicts\":{\"a\":true,\"b\":false}}",
    )
    .unwrap()
  let reversed = plan
    .decision_from_json(
      "{\"verdicts\":{\"b\":false,\"a\":true},\"time\":\"0\",\"position\":0}",
    )
    .unwrap()
  assert_eq(first.values(), [true, false])
  assert_eq(first.names(), reversed.names())
  assert_eq(first.values(), reversed.values())
  let claim = plan
    .decision_from_json(
      "{\"position\":0,\"time\":\"0\",\"verdicts\":{\"a\":false,\"b\":false}}",
    )
    .unwrap()
  assert_true(!plan.verify_decision([event(0L, true, false)], claim).unwrap())
}

///|
test "decision transport rejects invalid position representations" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p")]).unwrap()
  for
    position in [
      "-1", "0.5", "1000000", "2147483647", "1e300", "null", "true", "[]", "{}",
      "\"0\"",
    ] {
    let text = "{\"position\":" +
      position +
      ",\"time\":\"0\",\"verdicts\":{\"r\":true}}"
    assert_true(plan.decision_from_json(text) is Err(_), msg=text)
  }
  let limits = @moon-mtl.Limits::new(events=2).unwrap()
  let plan = @moon-mtl.Plan::from_strings([("r", "p")], limits~).unwrap()
  assert_true(
    plan.decision_from_json(
      "{\"position\":1,\"time\":\"0\",\"verdicts\":{\"r\":true}}",
    )
    is Ok(_),
  )
  assert_true(
    plan.decision_from_json(
      "{\"position\":2,\"time\":\"0\",\"verdicts\":{\"r\":true}}",
    )
    is Err(_),
  )
}

///|
test "decision transport rejects incorrect names and schema fields" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p")]).unwrap()
  for
    text in [
      "null", "[]", "{}", "{\"position\":0,\"time\":0,\"verdicts\":{\"r\":true}}",
      "{\"position\":0,\"time\":\"-1\",\"verdicts\":{\"r\":true}}", "{\"position\":0,\"time\":\"0\",\"verdicts\":{}}",
      "{\"position\":0,\"time\":\"0\",\"verdicts\":{\"other\":true}}", "{\"position\":0,\"time\":\"0\",\"verdicts\":{\"r\":1}}",
      "{\"position\":0,\"time\":\"0\",\"verdicts\":{\"r\":\"false\"}}", "{\"position\":0,\"time\":\"0\",\"verdicts\":{\"r\":null}}",
      "{\"position\":0,\"time\":\"0\",\"verdicts\":{\"r\":true,\"other\":false}}",
      "{\"position\":0,\"time\":\"0\",\"verdicts\":{\"r\":true,\"r\":false}}", "{\"position\":0,\"time\":\"0\",\"verdicts\":{\"r\":true},\"extra\":0}",
    ] {
    assert_true(plan.decision_from_json(text) is Err(_), msg=text)
  }
}
