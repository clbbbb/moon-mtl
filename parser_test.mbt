///|
fn event(time : Int64, p : Bool, q : Bool) -> @moon-mtl.Observation {
  @moon-mtl.Observation::new(time, Map([("p", p), ("q", q)])).unwrap()
}

///|
fn parsed_value(text : String, p : Bool, q : Bool) -> Bool {
  let formula = @moon-mtl.parse(text).unwrap()
  @moon-mtl.evaluate_reference(formula, [event(0L, p, q)], 0).unwrap()
}

///|
test "parser boolean truth tables and precedence" {
  for p in [false, true] {
    for q in [false, true] {
      assert_eq(parsed_value("p & q", p, q), p && q)
      assert_eq(parsed_value("p | q", p, q), p || q)
      assert_eq(parsed_value("p -> q", p, q), !p || q)
      assert_eq(parsed_value("!p", p, q), !p)
      assert_eq(parsed_value("!!p", p, q), p)
      assert_eq(parsed_value("true | p & q", p, q), true)
      assert_eq(parsed_value("(true | p) & q", p, q), q)
      assert_eq(parsed_value("p -> q -> p", p, q), !p || !q || p)
      assert_eq(parsed_value("(p -> q) -> p", p, q), !(!p || q) || p)
      assert_eq(parsed_value("!p & q | p", p, q), (!p && q) || p)
    }
  }
}

///|
test "parser temporal operators closed bounds and previous" {
  let trace = [
    event(0L, true, false),
    event(3L, false, true),
    event(8L, true, false),
  ]
  for
    (text, expected) in [
      ("once[5,8] p", true),
      ("once[0,4] q", false),
      ("historically[0,0] p", true),
      ("historically[5,8] p", false),
      ("previous q", true),
      ("p since[5,5] q", true),
      ("p since[8,8] p", false),
      ("previous once[0,3] p", true),
      ("p & once[0,9](p & !q)", true),
    ] {
    assert_eq(
      @moon-mtl.evaluate_reference(@moon-mtl.parse(text).unwrap(), trace, 2).unwrap(),
      expected,
    )
  }
}

///|
test "parser rejects ambiguous malformed and unsupported syntax" {
  for
    text in [
      "", " ", "p q", "p && q", "p || q", "p => q", "-> p", "p &", "!", "(p", "p)",
      "once p", "once[0] p", "once[,2] p", "once[0,] p", "once[-1,2] p", "once[2,1] p",
      "once[0,1)", "since[0,2] p", "p since q", "p since[0,1]", "1", "p + q", "p; q",
      "p: q", "\"p\"", "p @ q", "once[0,9223372036854775808] p",
    ] {
    assert_true(@moon-mtl.parse(text) is Err(_))
  }
}

///|
test "syntax diagnostics use scalar offsets and identify integer overflow" {
  assert_true(@moon-mtl.parse("p & @") is Err(@moon-mtl.SyntaxError(4, _)))
  assert_true(@moon-mtl.parse("é") is Err(@moon-mtl.SyntaxError(0, _)))
  assert_true(
    @moon-mtl.parse("once[0,9223372036854775808] p")
    is Err(@moon-mtl.SyntaxError(7, _)),
  )
  assert_true(@moon-mtl.parse("p q") is Err(@moon-mtl.SyntaxError(2, _)))
  assert_true(@moon-mtl.parse("(p") is Err(@moon-mtl.SyntaxError(2, _)))
}

///|
test "identifiers whitespace and exact Int64 maximum interval" {
  let formula = @moon-mtl.parse(
    " \t once [ 0 , 9223372036854775807 ] (device.p_1) \r\n",
  ).unwrap()
  let observation = @moon-mtl.Observation::new(
    9223372036854775807L,
    Map([("device.p_1", true)]),
  ).unwrap()
  assert_true(@moon-mtl.evaluate_reference(formula, [observation], 0).unwrap())
  assert_true(@moon-mtl.parse("a..b") is Ok(_))
  assert_true(@moon-mtl.parse(".a") is Err(_))
  assert_true(@moon-mtl.parse("1a") is Err(_))
  assert_true(@moon-mtl.parse("p\n->\tq") is Ok(_))
}

///|
test "parser enforces actual left-associated depth and syntax node limits" {
  let limits = @moon-mtl.Limits::new(nodes=8, depth=3).unwrap()
  assert_true(@moon-mtl.parse("p & q", limits~) is Ok(_))
  assert_true(
    @moon-mtl.parse("p & q & p & q", limits~) is Err(@moon-mtl.ResourceLimit(_)),
  )
  assert_true(
    @moon-mtl.parse("!!!!p", limits~) is Err(@moon-mtl.ResourceLimit(_)),
  )
  assert_true(@moon-mtl.parse("((((p))))", limits~) is Err(_))
  let nodes = @moon-mtl.Limits::new(nodes=2).unwrap()
  assert_true(@moon-mtl.parse("p & q", limits=nodes) is Err(_))
  let mut long = ""
  for _ in 0..<129 {
    long += "a"
  }
  assert_true(@moon-mtl.parse(long) is Err(_))
  let mut large = ""
  for _ in 0..<16385 {
    large += " "
  }
  assert_true(@moon-mtl.parse(large) is Err(_))
}
