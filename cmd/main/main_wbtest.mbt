///|
test "CLI event count validation rejects overflow and invalid strings" {
  assert_true(integer("1") is Ok(1))
  assert_true(integer("1000000") is Ok(1000000))
  for
    text in [
      "", "0", "-1", "1000001", "2147483648", "999999999999999999999999", "hello",
      "1.5",
    ] {
    assert_true(integer(text) is Err(_))
  }
}

///|
test "CLI dispatch validates command arity before I/O" {
  assert_true(run([]) is Ok(_))
  assert_true(run(["--help"]) is Ok(_))
  assert_true(run(["unknown"]) is Err(_))
  assert_true(run(["scenario", "lease"]) is Err(_))
  assert_true(run(["scenario", "lease", "2", "extra"]) is Err(_))
  assert_true(run(["unknown", "lease", "2"]) is Err(_))
  assert_true(run(["scenario", "unknown", "2"]) is Err(_))
  assert_true(run(["rules", "unknown"]) is Err(_))
  assert_true(run(["scenario", "lease", "0"]) is Err(_))
}

///|
test "CLI all commands execute on a small valid scenario" {
  assert_true(run(["scenario", "handshake", "2"]) is Ok(_))
  assert_true(run(["scenario", "lease", "2"]) is Ok(_))
  assert_true(run(["scenario", "recovery", "2"]) is Ok(_))
  assert_true(run(["rules", "handshake"]) is Ok(_))
  assert_true(run(["rules", "lease"]) is Ok(_))
  assert_true(run(["rules", "recovery"]) is Ok(_))
  assert_true(run(["export", "handshake", "2"]) is Ok(_))
  assert_true(run(["export", "lease", "2"]) is Ok(_))
  assert_true(run(["export", "recovery", "2"]) is Ok(_))
  assert_true(run(["bench", "handshake", "2"]) is Ok(_))
}
