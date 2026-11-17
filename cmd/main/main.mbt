///|
// Same native exit binding as MoonBit core/argparse; connection cleanup has
// already run when the command returns an error to main.
extern "c" fn process_exit(code : Int32) = "exit"

///|
async fn main {
  let options = match parse_options(@env.args()) {
    Ok(None) => {
      @stdio.stdout.write(usage())
      return
    }
    Ok(Some(options)) => options
    Err(message) => {
      @stdio.stderr.write("error: " + message + "\nUse --help for usage.\n")
      process_exit(2)
      return
    }
  }
  match run_command(options) {
    Ok(output) => @stdio.stdout.write(output + "\n")
    Err(message) => {
      @stdio.stderr.write("error: " + message + "\n")
      process_exit(1)
    }
  }
}

///|
async fn run_command(options : Options) -> Result[String, String] {
  let client = match
    @moonpv.Client::connect(
      options.host,
      options.port,
      unit_id=options.unit_id,
      timeout_ms=options.timeout_ms,
    ) {
    Ok(client) => client
    Err(message) => return Err(message)
  }
  defer client.close()
  if options.command != "sunspec" {
    let values = match
      (if options.command == "read-holding" {
        client.read_holding_registers(options.address, options.count)
      } else {
        client.read_input_registers(options.address, options.count)
      }) {
      Ok(values) => values
      Err(message) => return Err(message)
    }
    if options.json {
      let result : Json = {
        "schema_version": 1,
        "address": @json.to_json(options.address),
        "registers": @json.to_json(values),
      }
      return Ok(result.stringify(indent=2))
    }
    return Ok(
      values.mapi((i, value) => "\{options.address + i}\t\{value}").join("\n"),
    )
  }
  let device = match client.discover_sunspec(options.bases) {
    Ok(device) => device
    Err(message) => return Err(message)
  }
  let snapshots : Array[Snapshot] = []
  for model in device.models {
    if options.model_address is Some(address) && address != model.start_address {
      continue
    }
    if model.id == 103 {
      match
        client.read_inverter_103(device, start_address=model.start_address) {
        Ok(value) =>
          snapshots.push(inverter_snapshot(model.start_address, value))
        Err(message) =>
          return Err("Model 103 at \{model.start_address}: \{message}")
      }
    } else if model.id == 203 {
      match client.read_meter_203(device, start_address=model.start_address) {
        Ok(value) => snapshots.push(meter_snapshot(model.start_address, value))
        Err(message) =>
          return Err("Model 203 at \{model.start_address}: \{message}")
      }
    }
  }
  if snapshots.is_empty() {
    return Err(
      "no supported Model 103/203 at the requested address; inspect the device model map",
    )
  }
  // No successful partial snapshot: all selected reads must finish first.
  if options.json {
    let models = device.models.map(model => {
      let value : Json = {
        "id": @json.to_json(model.id),
        "address": @json.to_json(model.start_address),
        "length": @json.to_json(model.length),
      }
      value
    })
    let result : Json = {
      "schema_version": 1,
      "base_address": @json.to_json(device.base_address),
      "models": @json.to_json(models),
      "snapshots": @json.to_json(snapshots.map(snapshot_json)),
    }
    Ok(result.stringify(indent=2))
  } else {
    let lines = ["SunSpec base address: \{device.base_address}"]
    for model in device.models {
      lines.push(
        "Model \{model.id}: address \{model.start_address}, length \{model.length}",
      )
    }
    for snapshot in snapshots {
      lines.push("Model \{snapshot.id} at \{snapshot.address}:")
      for point in snapshot.points {
        let value = match point.value {
          Some(value) => value
          None => point.status
        }
        lines.push("  \{point.name}: \{value} \{point.unit}")
      }
    }
    Ok(lines.join("\n"))
  }
}
