///|
fn usage() -> String {
  "MoonPV - SunSpec solar-device reader for MoonBit\n\n" +
  "Usage:\n" +
  "  moon run cmd/main -- sunspec <host> <port> <unit> [base-address]\n" +
  "  moon run cmd/main -- read-holding <host> <port> <unit> <address> <count>\n" +
  "  moon run cmd/main -- read-input <host> <port> <unit> <address> <count>\n"
}

///|
fn parse_int(value : String, label : String) -> Int32 {
  @string.parse_int(value) catch {
    _ => fail(label + " must be an integer: " + value)
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() == 2 && (args[1] == "--help" || args[1] == "-h") {
    println(usage())
    return
  }
  if args.length() < 2 {
    fail(usage())
  }
  let command = args[1]
  if command == "sunspec" {
    if args.length() != 5 && args.length() != 6 {
      fail(usage())
    }
    let host = args[2]
    let port = parse_int(args[3], "port")
    let unit_id = parse_int(args[4], "unit ID")
    let client = match @moonpv.Client::connect(host, port, unit_id~) {
      Ok(client) => client
      Err(message) => fail(message)
    }
    defer client.close()
    let candidates = if args.length() == 6 {
      [parse_int(args[5], "base address")]
    } else {
      [0, 40000, 50000]
    }
    let device = match client.discover_sunspec(candidates) {
      Ok(device) => device
      Err(message) => fail(message)
    }
    print_sunspec_device(device)
    match client.read_inverter_103(device) {
      Ok(snapshot) => print_inverter_snapshot(snapshot)
      Err(message) => println("Model 103 summary unavailable: " + message)
    }
    match client.read_meter_203(device) {
      Ok(snapshot) => print_meter_snapshot(snapshot)
      Err(message) => println("Model 203 summary unavailable: " + message)
    }
    return
  }
  if args.length() != 7 {
    fail(usage())
  }
  let host = args[2]
  let port = parse_int(args[3], "port")
  let unit_id = parse_int(args[4], "unit ID")
  let address = parse_int(args[5], "address")
  let client = match @moonpv.Client::connect(host, port, unit_id~) {
    Ok(client) => client
    Err(message) => fail(message)
  }
  defer client.close()
  match command {
    "read-holding" => {
      let count = parse_int(args[6], "count")
      match client.read_holding_registers(address, count) {
        Ok(values) => print_registers(address, values)
        Err(message) => fail(message)
      }
    }
    "read-input" => {
      let count = parse_int(args[6], "count")
      match client.read_input_registers(address, count) {
        Ok(values) => print_registers(address, values)
        Err(message) => fail(message)
      }
    }
    _ => fail("unknown command: " + command + "\n\n" + usage())
  }
}

///|
fn print_registers(start : Int32, values : Array[Int32]) -> Unit {
  for index in 0..<values.length() {
    println((start + index).to_string() + "\t" + values[index].to_string())
  }
}

///|
fn print_sunspec_device(device : @moonpv.SunSpecDevice) -> Unit {
  println("SunSpec base address: " + device.base_address.to_string())
  println("Models:")
  for model in device.models {
    println(
      "  ID " +
      model.id.to_string() +
      "  address " +
      model.start_address.to_string() +
      "  length " +
      model.length.to_string(),
    )
  }
}

///|
fn print_inverter_snapshot(snapshot : @moonpv.Inverter103Snapshot) -> Unit {
  println("Model 103 (three-phase inverter):")
  print_scaled_point(
    "  Phase A voltage",
    snapshot.phase_voltage_a,
    snapshot.voltage_scale_factor,
    "V",
  )
  print_scaled_point(
    "  Phase B voltage",
    snapshot.phase_voltage_b,
    snapshot.voltage_scale_factor,
    "V",
  )
  print_scaled_point(
    "  Phase C voltage",
    snapshot.phase_voltage_c,
    snapshot.voltage_scale_factor,
    "V",
  )
  print_scaled_point(
    "  Active power",
    snapshot.active_power,
    snapshot.active_power_scale_factor,
    "W",
  )
  print_scaled_point(
    "  AC frequency",
    snapshot.frequency,
    snapshot.frequency_scale_factor,
    "Hz",
  )
}

///|
fn print_scaled_point(
  label : String,
  value : Int32?,
  scale_factor : Int32?,
  unit : String,
) -> Unit {
  match (value, scale_factor) {
    (Some(raw), Some(sf)) =>
      println(
        label + ": " + raw.to_string() + " × 10^" + sf.to_string() + " " + unit,
      )
    (Some(raw), None) =>
      println(
        label + ": " + raw.to_string() + " (scale factor unavailable) " + unit,
      )
    (None, _) => println(label + ": not implemented by device")
  }
}

///|
fn print_meter_snapshot(snapshot : @moonpv.Meter203Snapshot) -> Unit {
  println("Model 203 (three-phase meter):")
  print_scaled_point(
    "  Phase A voltage",
    snapshot.phase_voltage_a,
    snapshot.voltage_scale_factor,
    "V",
  )
  print_scaled_point(
    "  Active power",
    snapshot.active_power,
    snapshot.active_power_scale_factor,
    "W",
  )
  print_scaled_point(
    "  AC frequency",
    snapshot.frequency,
    snapshot.frequency_scale_factor,
    "Hz",
  )
  print_scaled_int64_point(
    "  Imported energy",
    snapshot.imported_energy,
    snapshot.energy_scale_factor,
    "Wh",
  )
  print_scaled_int64_point(
    "  Exported energy",
    snapshot.exported_energy,
    snapshot.energy_scale_factor,
    "Wh",
  )
}

///|
fn print_scaled_int64_point(
  label : String,
  value : Int64?,
  scale_factor : Int32?,
  unit : String,
) -> Unit {
  match (value, scale_factor) {
    (Some(raw), Some(sf)) =>
      println(
        label + ": " + raw.to_string() + " × 10^" + sf.to_string() + " " + unit,
      )
    (Some(raw), None) =>
      println(
        label + ": " + raw.to_string() + " (scale factor unavailable) " + unit,
      )
    (None, _) => println(label + ": not implemented by device")
  }
}

///|
fn[T] fail(message : String) -> T {
  println("error: " + message)
  abort(message)
}
