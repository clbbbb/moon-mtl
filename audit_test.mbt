///|
test "audit counts distinct failure runs without retaining the trace" {
  let plan = @moon-mtl.Plan::from_strings([("p", "p"), ("inverse", "!p")]).unwrap()
  let audit = @moon-mtl.Audit::new(plan)
  let values = [true, false, false, true, false, false, false, true]
  for i in 0..<values.length() {
    audit.push(event((i * 3).to_int64(), values[i], false)).unwrap() |> ignore
  }
  let summary = audit.summary("p").unwrap()
  assert_eq(summary.accepted, 3)
  assert_eq(summary.rejected, 5)
  assert_eq(summary.failure_runs, 2)
  assert_eq(summary.current_failure_run, 0)
  assert_eq(summary.longest_failure_run, 3)
  assert_eq(summary.first_failure.unwrap().position, 1)
  assert_eq(summary.first_failure.unwrap().time, 3L)
  assert_eq(summary.last_failure.unwrap().position, 6)
  assert_eq(summary.last_transition.unwrap().position, 7)
  assert_eq(summary.latest, Some(true))
  let inverse = audit.summary("inverse").unwrap()
  assert_eq(inverse.accepted, 5)
  assert_eq(inverse.rejected, 3)
  assert_eq(inverse.failure_runs, 3)
  assert_eq(inverse.current_failure_run, 1)
  assert_eq(inverse.longest_failure_run, 1)
  assert_eq(audit.stats().processed, 8)
  assert_eq(audit.last_decision().unwrap().values(), [true, false])
  assert_true(audit.summary("unknown") is None)
  assert_true(audit.explain("p") is Ok(_))
}

///|
test "audit initial and immutable snapshot behavior" {
  let plan = @moon-mtl.Plan::from_strings([("r", "p")]).unwrap()
  let audit = @moon-mtl.Audit::new(plan)
  let old = audit.summary("r").unwrap()
  assert_eq(old.accepted, 0)
  assert_eq(old.rejected, 0)
  assert_eq(old.failure_runs, 0)
  assert_eq(old.latest, None)
  assert_true(old.first_failure is None)
  assert_true(old.last_failure is None)
  assert_true(old.last_transition is None)
  assert_true(audit.last_decision() is None)
  assert_true(audit.explain("r") is Err(_))
  let copy = audit.summaries()
  copy.clear()
  assert_eq(audit.summaries().length(), 1)
  audit.push(event(0L, false, false)).unwrap() |> ignore
  assert_eq(old.rejected, 0)
  let latest = audit.summary("r").unwrap()
  assert_eq(latest.failure_runs, 1)
  assert_eq(latest.current_failure_run, 1)
  assert_eq(latest.latest, Some(false))
  assert_true(latest.last_transition is None)
}

///|
test "failed updates preserve every audit counter and transition" {
  let limits = @moon-mtl.Limits::new(candidates=1).unwrap()
  let plan = @moon-mtl.Plan::from_strings([("r", "once[0,2] p")], limits~).unwrap()
  let audit = @moon-mtl.Audit::new(plan)
  audit.push(event(0L, true, false)).unwrap() |> ignore
  let before = audit.summary("r").unwrap()
  assert_true(audit.push(event(1L, true, false)) is Err(_))
  assert_true(audit.push(event(0L, false, false)) is Err(_))
  let after = audit.summary("r").unwrap()
  assert_eq(after.accepted, before.accepted)
  assert_eq(after.rejected, before.rejected)
  assert_eq(after.failure_runs, before.failure_runs)
  assert_eq(after.latest, before.latest)
  assert_true(after.first_failure is None)
  assert_true(after.last_failure is None)
  assert_true(after.last_transition is None)
  assert_eq(audit.stats().processed, 1)
  assert_eq(audit.push(event(3L, false, false)).unwrap().values(), [false])
  assert_eq(audit.summary("r").unwrap().rejected, 1)
  assert_eq(audit.summary("r").unwrap().last_transition.unwrap().time, 3L)
}
