///|
test "pointwise windows and since use observed positions and closed endpoints" {
  let window = @moon-mtl.Interval::new(2L, 5L).unwrap()
  let trace = [
    @moon-mtl.Observation::new(0L, Map([("p", true), ("q", true)])).unwrap(),
    @moon-mtl.Observation::new(2L, Map([("p", true), ("q", false)])).unwrap(),
    @moon-mtl.Observation::new(5L, Map([("p", true), ("q", false)])).unwrap(),
    @moon-mtl.Observation::new(6L, Map([("p", false), ("q", false)])).unwrap(),
  ]
  let once = @moon-mtl.Once(window, @moon-mtl.Atom("q"))
  assert_eq(@moon-mtl.evaluate_reference(once, trace, 0).unwrap(), false)
  assert_eq(@moon-mtl.evaluate_reference(once, trace, 2).unwrap(), true)
  assert_eq(@moon-mtl.evaluate_reference(once, trace, 3).unwrap(), false)
  let since = @moon-mtl.Since(window, @moon-mtl.Atom("p"), @moon-mtl.Atom("q"))
  assert_eq(@moon-mtl.evaluate_reference(since, trace, 2).unwrap(), true)
  assert_eq(@moon-mtl.evaluate_reference(since, trace, 3).unwrap(), false)
}
