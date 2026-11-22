///|
test "every two-chunk split matches batch replay" {
  let plan = @moon-mtl.Plan::from_strings([
    ("a", "once[1,5] p"),
    ("b", "p since[0,4] q"),
  ]).unwrap()
  let text = event(0L, true, true).to_json() +
    "\r\n" +
    event(2L, true, false).to_json() +
    "\n" +
    event(7L, false, true).to_json()
  let expected = @moon-mtl.Monitor::new(plan).replay_jsonl(text).unwrap()
  for split in 0..<(text.length() + 1) {
    let session = @moon-mtl.JsonlSession::new(plan)
    let actual = session.feed(text[:split].to_owned()).unwrap()
    for decision in session.feed(text[split:].to_owned()).unwrap() {
      actual.push(decision)
    }
    for decision in session.finish().unwrap() {
      actual.push(decision)
    }
    assert_eq(actual.length(), expected.length())
    for i in 0..<actual.length() {
      assert_eq(actual[i].to_json(), expected[i].to_json())
    }
    assert_eq(session.stats().processed, 3)
    assert_true(session.is_finished())
    assert_eq(session.buffered_units(), 0)
    assert_true(session.error() is None)
  }
}

///|
test "single code-unit chunks preserve escaped JSON and Int64 timestamps" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p")]).unwrap()
  let text = "{\"time\":\"9007199254740993\",\"values\":{\"\\u0070\":true}}\r\n"
  let session = @moon-mtl.JsonlSession::new(plan)
  let decisions = []
  for i in 0..<text.length() {
    for decision in session.feed(text[i:i + 1].to_owned()).unwrap() {
      decisions.push(decision)
    }
  }
  assert_eq(decisions.length(), 1)
  assert_eq(decisions[0].timestamp(), 9007199254740993L)
  assert_eq(decisions[0].values(), [true])
  assert_eq(session.finish().unwrap().length(), 0)
}

///|
test "finished session is idempotent but cannot accept another chunk" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p")]).unwrap()
  let session = @moon-mtl.JsonlSession::new(plan)
  assert_eq(session.feed("").unwrap().length(), 0)
  assert_eq(session.finish().unwrap().length(), 0)
  assert_eq(session.finish().unwrap().length(), 0)
  assert_true(session.feed("") is Err(_))
  assert_true(session.last_decision() is None)
  assert_true(session.explain("r") is Err(_))
  assert_true(session.is_finished())
  assert_true(session.error() is None)
}

///|
test "failed session seals after accepted prefix and discards suffix" {
  let plan = @moon-mtl.Plan::from_strings([("r", "previous p")]).unwrap()
  let session = @moon-mtl.JsonlSession::new(plan)
  let first = event(0L, true, false).to_json()
  let second = event(1L, false, false).to_json()
  assert_true(session.feed(first + "\ninvalid\n" + second + "\n") is Err(_))
  assert_eq(session.stats().processed, 1)
  assert_true(session.error() is Some(_))
  assert_true(!session.is_finished())
  assert_eq(session.buffered_units(), 0)
  assert_eq(session.last_decision().unwrap().values(), [false])
  assert_true(session.feed(second) is Err(_))
  assert_true(session.finish() is Err(_))
  assert_eq(session.stats().processed, 1)
}

///|
test "session catches errors in unterminated last record and blank line" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p")]).unwrap()
  for tail in ["garbage", " ", "\r", "{", "[]"] {
    let session = @moon-mtl.JsonlSession::new(plan)
    assert_true(session.feed(tail) is Ok(_))
    assert_true(session.finish() is Err(_))
    assert_eq(session.stats().processed, 0)
    assert_eq(session.buffered_units(), 0)
  }
  let session = @moon-mtl.JsonlSession::new(plan)
  assert_true(session.feed("\n") is Err(_))
}

///|
test "feed_each delivers the whole accepted prefix before reporting a bad line" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p")]).unwrap()
  let session = @moon-mtl.JsonlSession::new(plan)
  let first = event(0L, true, false).to_json()
  let second = event(1L, false, false).to_json()
  let positions = []
  let result = session.feed_each(first + "\n" + second + "\ninvalid\n", decision => {
    positions.push(decision.position())
  })
  assert_true(result is Err(_))
  assert_eq(positions, [0, 1])
  assert_eq(session.stats().processed, 2)
}

///|
test "session enforces unfinished record and chunk budgets" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p")]).unwrap()
  let session = @moon-mtl.JsonlSession::new(plan)
  let fragment = "x".repeat(524288)
  assert_true(session.feed(fragment) is Ok(_))
  assert_eq(session.buffered_units(), 524288)
  assert_true(session.feed(fragment) is Ok(_))
  assert_eq(session.buffered_units(), 1048576)
  assert_true(session.feed("x") is Err(_))
  assert_eq(session.buffered_units(), 0)
  assert_eq(session.stats().processed, 0)
  let session = @moon-mtl.JsonlSession::new(plan)
  assert_true(session.feed("x".repeat(1048577)) is Err(_))
  assert_true(session.error() is Some(_))
}

///|
test "session monotonicity errors identify the physical JSONL line" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p")]).unwrap()
  let session = @moon-mtl.JsonlSession::new(plan)
  let text = event(4L, true, false).to_json() +
    "\n" +
    event(4L, false, false).to_json() +
    "\n"
  assert_true(session.feed(text) is Err(_))
  assert_true(session.error().unwrap().message().contains("line 2"))
  assert_eq(session.stats().processed, 1)
}

///|
test "callback cannot finish or reenter the active JSONL session" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p")]).unwrap()
  let session = @moon-mtl.JsonlSession::new(plan)
  let records = event(0L, true, false).to_json() +
    "\n" +
    event(1L, false, false).to_json() +
    "\n"
  let positions = []
  let blocked = []
  session
  .feed_each(records, decision => {
    positions.push(decision.position())
    blocked.push(session.finish() is Err(_))
    blocked.push(session.feed("") is Err(_))
  })
  .unwrap()
  assert_eq(positions, [0, 1])
  assert_eq(blocked, [true, true, true, true])
  assert_true(!session.is_finished())
  assert_eq(session.finish().unwrap().length(), 0)
  assert_true(session.is_finished())
}
