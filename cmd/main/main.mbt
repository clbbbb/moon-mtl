///|
extern "js" fn clock() -> Double =
  #| () => performance.now()

///|
extern "js" fn fail(message : String) -> Unit =
  #| message => { console.error(message); process.exitCode = 2; }

///|
#module("node:fs")
extern "js" fn raw_read(path : String, encoding : String) -> String = "readFileSync"

///|
extern "js" fn bounded_read(
  path : String,
  read : (String, String) -> String,
) -> String =
  #| (path, read) => {
  #|   try {
  #|     const text = read(path, "utf8");
  #|     return text.length <= 16777216 ? "=" + text : "!file exceeds 16 MiB code units";
  #|   } catch(e) { return "!" + String(e.message); }
  #| }

///|
fn read(path : String) -> Result[String, @mtl.MonitorError] {
  let result = bounded_read(path, raw_read)
  if result.has_prefix("!") {
    Err(@mtl.InvalidData(result[1:].to_owned()))
  } else {
    Ok(result[1:].to_owned())
  }
}

///|
fn integer(text : String) -> Result[Int32, @mtl.MonitorError] {
  try {
    let value = @string.parse_int(text[:])
    if value < 1 || value > 1000000 {
      Err(@mtl.InvalidData("event count must be 1..1000000"))
    } else {
      Ok(value)
    }
  } catch {
    _ => Err(@mtl.InvalidData("invalid event count"))
  }
}

///|
fn replay(rules : String, events : String) -> Result[Unit, @mtl.MonitorError] {
  let rules = match read(rules) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let plan = match @mtl.Plan::from_json(rules) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let events = match read(events) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let monitor = @mtl.Monitor::new(plan)
  let lines = events.split("\n").to_array()
  for i in 0..<lines.length() {
    if i == lines.length() - 1 && lines[i].is_empty() {
      break
    }
    let record = match @mtl.Observation::from_json(lines[i].to_owned()) {
      Err(e) =>
        return Err(
          @mtl.InvalidData("line " + (i + 1).to_string() + ": " + e.message()),
        )
      Ok(value) => value
    }
    match monitor.push(record) {
      Err(e) =>
        return Err(
          @mtl.InvalidData("line " + (i + 1).to_string() + ": " + e.message()),
        )
      Ok(value) => println(value.to_json())
    }
  }
  Ok(())
}

///|
fn scenario(
  name : String,
  count : Int32,
  export_records : Bool,
) -> Result[Unit, @mtl.MonitorError] {
  let scenario = match @scenarios.Scenario::new(name, count) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  if export_records {
    for record in scenario.trace() {
      println(record.to_json())
    }
    return Ok(())
  }
  let summary = match scenario.run() {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  println(
    "scenario=" +
    name +
    " events=" +
    summary.events.to_string() +
    " checks=" +
    summary.checks.to_string() +
    " failures=" +
    summary.failures.to_string() +
    " checksum=" +
    summary.checksum.to_string() +
    " nodes=" +
    summary.nodes.to_string() +
    " peak_candidates=" +
    summary.peak_candidates.to_string(),
  )
  Ok(())
}

///|
fn benchmark(name : String, count : Int32) -> Result[Unit, @mtl.MonitorError] {
  let scenario = match @scenarios.Scenario::new(name, count) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  let plan = scenario.plan().unwrap()
  let records = scenario.trace()
  let singles = scenario
    .rules()
    .map(rule => @mtl.Plan::from_strings([rule]).unwrap())
  for repetition in 0..<7 {
    let shared = @mtl.Monitor::new(plan)
    let monitors = singles.map(single => @mtl.Monitor::new(single))
    let reference = @mtl.Reference::new(plan, records).unwrap()
    let mut checksum_shared = 1
    let start = clock()
    for record in records {
      checksum_shared = @scenarios.verdict_checksum(
        checksum_shared,
        shared.push(record).unwrap().values(),
      )
    }
    let shared_ms = clock() - start
    let mut checksum_single = 1
    let start = clock()
    for record in records {
      let values : Array[Bool] = []
      for monitor in monitors {
        values.push(monitor.push(record).unwrap().values()[0])
      }
      checksum_single = @scenarios.verdict_checksum(checksum_single, values)
    }
    let independent_ms = clock() - start
    let mut checksum_reference = 1
    let mut reference_steps = 0L
    let start = clock()
    for i in 0..<records.length() {
      checksum_reference = @scenarios.verdict_checksum(
        checksum_reference,
        reference.evaluate(i).unwrap().values(),
      )
      reference_steps += reference.last_steps().to_int64()
    }
    let reference_ms = clock() - start
    if checksum_shared != checksum_single ||
      checksum_shared != checksum_reference {
      return Err(@mtl.InvalidData("benchmark verdict checksum mismatch"))
    }
    let mut independent_nodes = 0
    let mut independent_peak = 0
    for monitor in monitors {
      independent_nodes += monitor.stats().graph_nodes
      independent_peak += monitor.stats().peak_candidates
    }
    let fields : Map[String, Json] = Map([
      ("scenario", Json::string(name)),
      ("events", Json::number(count.to_double())),
      ("repetition", Json::number(repetition.to_double())),
      ("shared_ms", Json::number(shared_ms)),
      ("independent_ms", Json::number(independent_ms)),
      ("reference_ms", Json::number(reference_ms)),
      ("shared_nodes", Json::number(plan.node_count().to_double())),
      ("independent_nodes", Json::number(independent_nodes.to_double())),
      (
        "peak_candidates",
        Json::number(shared.stats().peak_candidates.to_double()),
      ),
      ("sum_independent_peaks", Json::number(independent_peak.to_double())),
      ("reference_steps", Json::string(reference_steps.to_string())),
      ("checksum", Json::number(checksum_shared.to_double())),
    ])
    println(Json::object(fields).stringify())
  }
  Ok(())
}

///|
fn run(args : Array[String]) -> Result[Unit, @mtl.MonitorError] {
  if args.length() == 0 || args == ["--help"] {
    println(
      "MoonMTL\n  replay <rules.json> <events.jsonl>\n  scenario <handshake|lease|recovery> <count>\n  export <scenario> <count>\n  bench <scenario> <count>\n  rules <scenario>",
    )
    return Ok(())
  }
  if args.length() == 2 && args[0] == "rules" {
    match @scenarios.Scenario::new(args[1], 1) {
      Err(e) => return Err(e)
      Ok(value) => println(value.plan().unwrap().to_json())
    }
    return Ok(())
  }
  if args.length() != 3 {
    return Err(@mtl.InvalidData("invalid arguments; use --help"))
  }
  if args[0] == "replay" {
    return replay(args[1], args[2])
  }
  let count = match integer(args[2]) {
    Err(e) => return Err(e)
    Ok(value) => value
  }
  match args[0] {
    "scenario" => scenario(args[1], count, false)
    "export" => scenario(args[1], count, true)
    "bench" => benchmark(args[1], count)
    _ => Err(@mtl.InvalidData("unknown command; use --help"))
  }
}

///|
fn main {
  let args = @env.args()
  match run(args[2:].to_owned()) {
    Ok(_) => ()
    Err(e) => fail(e.message())
  }
}
