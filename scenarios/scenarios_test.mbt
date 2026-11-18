///|
test "all scenario verdicts agree with reference and evidence" {
  for name in ["handshake", "lease", "recovery"] {
    let scenario = @scenarios.Scenario::new(name, 240).unwrap()
    let plan = scenario.plan().unwrap()
    let trace = scenario.trace()
    let online = @mtl.Monitor::new(plan)
    let reference = @mtl.Reference::new(plan, trace).unwrap()
    let mut failures = 0
    let mut checksum = 1
    for i in 0..<trace.length() {
      let decision = online.push(trace[i]).unwrap()
      assert_eq(
        decision.values(),
        reference.evaluate(i).unwrap().values(),
        msg=name + " at " + i.to_string(),
      )
      for rule in plan.rule_names() {
        assert_true(
          plan.verify_evidence(trace, online.explain(rule).unwrap()).unwrap(),
        )
      }
      checksum = @scenarios.verdict_checksum(checksum, decision.values())
      for value in decision.values() {
        if !value {
          failures += 1
        }
      }
    }
    let summary = scenario.run().unwrap()
    assert_eq(summary.checksum, checksum)
    assert_eq(summary.failures, failures)
    assert_true(summary.failures > 0)
    assert_true(summary.failures < summary.checks)
    assert_eq(summary.events, 240)
    assert_eq(summary.checks, 1200)
  }
}

///|
test "scenario arguments and defensive copies" {
  assert_true(@scenarios.Scenario::new("unknown", 20) is Err(_))
  assert_true(@scenarios.Scenario::new("lease", 0) is Err(_))
  assert_true(@scenarios.Scenario::new("lease", 1000001) is Err(_))
  let scenario = @scenarios.Scenario::new("lease", 30).unwrap()
  assert_eq(scenario.name(), "lease")
  scenario.trace().clear()
  scenario.rules().clear()
  assert_eq(scenario.trace().length(), 30)
  assert_eq(scenario.rules().length(), 5)
}
