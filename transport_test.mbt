///|
test "observation transport preserves maximum timestamps and dotted atoms" {
  for time in [0L, 1L, 9007199254740993L, 9223372036854775807L] {
    let original = @moon-mtl.Observation::new(
      time,
      Map([("device.ready", true), ("lease_ok", false)]),
    ).unwrap()
    let restored = @moon-mtl.Observation::from_json(original.to_json()).unwrap()
    assert_eq(restored.timestamp(), time)
    assert_eq(restored.value("device.ready"), Some(true))
    assert_eq(restored.value("lease_ok"), Some(false))
    assert_eq(restored.value("missing"), None)
  }
}

///|
test "observation decoder rejects ambiguous or lossy representations" {
  for
    text in [
      "null", "[]", "{}", "true", "0", "\"text\"", "{\"time\":0,\"values\":{}}",
      "{\"time\":\"-1\",\"values\":{}}", "{\"time\":\"+1\",\"values\":{}}", "{\"time\":\"01\",\"values\":{}}",
      "{\"time\":\"\",\"values\":{}}", "{\"time\":\"1.0\",\"values\":{}}", "{\"time\":\"1e3\",\"values\":{}}",
      "{\"time\":\" 1\",\"values\":{}}", "{\"time\":\"9223372036854775808\",\"values\":{}}",
      "{\"time\":\"18446744073709551615\",\"values\":{}}", "{\"time\":\"0\",\"values\":null}",
      "{\"time\":\"0\",\"values\":[]}", "{\"time\":\"0\",\"values\":{\"p\":0}}",
      "{\"time\":\"0\",\"values\":{\"p\":\"true\"}}", "{\"time\":\"0\",\"values\":{\"p\":null}}",
      "{\"time\":\"0\",\"values\":{\"p\":true,\"p\":false}}", "{\"time\":\"0\",\"time\":\"1\",\"values\":{}}",
      "{\"time\":\"0\",\"values\":{},\"extra\":true}", "{\"time\":\"0\",\"value\":{}}",
      "{\"time\":\"0\",\"values\":{\"bad name\":true}}", "{\"time\":\"0\",\"values\":{}} trailing",
    ] {
    assert_true(@moon-mtl.Observation::from_json(text) is Err(_), msg=text)
  }
}

///|
test "rule transport reconstructs shared nodes and preserves rule order" {
  let original = @moon-mtl.Plan::from_strings([
    ("first", "p -> once[0,9] q"),
    ("second", "once[0,9] q"),
    ("third", "previous p"),
  ]).unwrap()
  let restored = @moon-mtl.Plan::from_json(original.to_json()).unwrap()
  assert_eq(restored.rule_names(), original.rule_names())
  assert_eq(restored.node_count(), original.node_count())
  let a = @moon-mtl.Monitor::new(original)
  let b = @moon-mtl.Monitor::new(restored)
  for i in 0..<20 {
    let observation = event(i.to_int64(), i % 2 == 0, i % 3 == 0)
    assert_eq(
      a.push(observation).unwrap().values(),
      b.push(observation).unwrap().values(),
    )
  }
}

///|
test "rule transport validates version structure syntax and receiver budgets" {
  for
    text in [
      "{}", "[]", "null", "{\"version\":1,\"rules\":[]}", "{\"version\":\"2\",\"rules\":[]}",
      "{\"version\":\"1\",\"rules\":[]}", "{\"version\":\"1\",\"rules\":{}}", "{\"version\":\"1\",\"rules\":[null]}",
      "{\"version\":\"1\",\"rules\":[{\"name\":\"r\"}]}", "{\"version\":\"1\",\"rules\":[{\"name\":1,\"formula\":\"p\"}]}",
      "{\"version\":\"1\",\"rules\":[{\"name\":\"r\",\"formula\":true}]}", "{\"version\":\"1\",\"rules\":[{\"name\":\"r\",\"formula\":\"p\",\"extra\":0}]}",
      "{\"version\":\"1\",\"rules\":[{\"name\":\"r\",\"formula\":\"once[9,1] p\"}]}",
      "{\"version\":\"1\",\"rules\":[{\"name\":\"r\",\"formula\":\"p\"},{\"name\":\"r\",\"formula\":\"q\"}]}",
      "{\"version\":\"1\",\"rules\":[],\"limits\":{}}",
    ] {
    assert_true(@moon-mtl.Plan::from_json(text) is Err(_), msg=text)
  }
  let original = @moon-mtl.Plan::from_strings([("a", "p"), ("b", "q")]).unwrap()
  let limits = @moon-mtl.Limits::new(nodes=1).unwrap()
  assert_true(@moon-mtl.Plan::from_json(original.to_json(), limits~) is Err(_))
}

///|
test "JSONL accepts LF CRLF and trailing newline with the same verdicts" {
  let plan = @moon-mtl.Plan::from_strings([("recent", "once[1,3] p")]).unwrap()
  let first = event(0L, true, false).to_json()
  let second = event(2L, false, false).to_json()
  for separator in ["\n", "\r\n"] {
    for trailing in ["", separator] {
      let monitor = @moon-mtl.Monitor::new(plan)
      let decisions = monitor
        .replay_jsonl(first + separator + second + trailing)
        .unwrap()
      assert_eq(decisions.length(), 2)
      assert_eq(decisions[0].values(), [false])
      assert_eq(decisions[1].values(), [true])
      assert_eq(monitor.stats().processed, 2)
    }
  }
  assert_eq(@moon-mtl.Monitor::new(plan).replay_jsonl("").unwrap().length(), 0)
}

///|
test "JSONL commits successful prefix and never the failed record" {
  let plan = @moon-mtl.Plan::from_strings([("p", "previous p")]).unwrap()
  let monitor = @moon-mtl.Monitor::new(plan)
  let good = event(0L, true, false).to_json()
  assert_true(
    monitor.replay_jsonl(
      good + "\ninvalid\n" + event(1L, false, false).to_json(),
    )
    is Err(_),
  )
  assert_eq(monitor.stats().processed, 1)
  assert_eq(monitor.push(event(1L, false, false)).unwrap().values(), [true])
  assert_true(monitor.replay_jsonl(event(1L, false, false).to_json()) is Err(_))
  assert_eq(monitor.stats().processed, 2)
  assert_true(monitor.replay_jsonl("\n") is Err(_))
  assert_eq(monitor.stats().processed, 2)
}

///|
test "decision JSON includes string timestamp and all named verdicts" {
  let plan = @moon-mtl.Plan::from_strings([("pass", "p"), ("fail", "q")]).unwrap()
  let decision = @moon-mtl.Monitor::new(plan)
    .push(event(9007199254740993L, true, false))
    .unwrap()
  let text = decision.to_json()
  assert_true(text.contains("9007199254740993"))
  assert_true(text.contains("\"pass\":true"))
  assert_true(text.contains("\"fail\":false"))
  assert_true(text.contains("\"position\":0"))
}
