///|
struct Options {
  command : String
  host : String
  port : Int32
  unit_id : Int32
  address : Int32
  count : Int32
  bases : Array[Int32]
  model_address : Int32?
  timeout_ms : Int32
  json : Bool
}

///|
fn usage() -> String {
  "MoonPV - SunSpec solar-device reader for MoonBit\n\nUsage:\n" +
  "  moonpv sunspec <host> <port> <unit> [base-address] [options]\n" +
  "  moonpv read-holding <host> <port> <unit> <address> <count> [options]\n" +
  "  moonpv read-input <host> <port> <unit> <address> <count> [options]\n\n" +
  "From source: replace moonpv with moon run cmd/main --\n\n" +
  "Options:\n  --timeout-ms N       connect/exchange deadline, 1..600000 (default 3000)\n" +
  "  --model-address N    select a Model 103/203 instance (sunspec only)\n" +
  "  --json               output JSON with exact decimal strings\n  --help               show this help\n\n" +
  "Exit codes: 0 success; 1 device/transport failure; 2 invalid command/arguments.\n"
}

///|
fn integer(value : String, label : String) -> Result[Int32, String] {
  Ok(@string.parse_int(value)) catch {
    _ => Err(label + " must be an integer: " + value)
  }
}

///|
// No socket is created before all arguments have been validated.
fn parse_options(args : Array[String]) -> Result[Options?, String] {
  if args.length() == 2 && (args[1] == "--help" || args[1] == "-h") {
    return Ok(None)
  }
  if args.length() < 2 {
    return Err("a command is required")
  }
  let command = args[1]
  if command != "sunspec" &&
    command != "read-holding" &&
    command != "read-input" {
    return Err("unknown command: " + command)
  }
  let positional : Array[String] = []
  let mut timeout_ms = 3000
  let mut model_address : Int32? = None
  let mut json = false
  let mut saw_timeout = false
  let mut i = 2
  while i < args.length() {
    match args[i] {
      "--json" => {
        if json {
          return Err("--json was specified more than once")
        }
        json = true
      }
      "--timeout-ms" | "--model-address" => {
        let name = args[i]
        if i + 1 >= args.length() {
          return Err("missing value for " + name)
        }
        i = i + 1
        let value = match integer(args[i], name) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        if name == "--timeout-ms" {
          if saw_timeout {
            return Err("--timeout-ms was specified more than once")
          }
          if value < 1 || value > 600000 {
            return Err("timeout must be between 1 and 600000 milliseconds")
          }
          timeout_ms = value
          saw_timeout = true
        } else {
          if command != "sunspec" {
            return Err("--model-address requires the sunspec command")
          }
          if model_address is Some(_) {
            return Err("--model-address was specified more than once")
          }
          if value < 0 || value > 65534 {
            return Err("model address must be between 0 and 65534")
          }
          model_address = Some(value)
        }
      }
      other => {
        if other.has_prefix("--") {
          return Err("unknown option: " + other)
        }
        positional.push(other)
      }
    }
    i = i + 1
  }
  if (
      command == "sunspec" &&
      positional.length() != 3 &&
      positional.length() != 4
    ) ||
    (command != "sunspec" && positional.length() != 5) {
    return Err("incorrect number of arguments for " + command)
  }
  let host = positional[0]
  if host.is_empty() {
    return Err("host must not be empty")
  }
  let port = match integer(positional[1], "port") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let unit_id = match integer(positional[2], "unit ID") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if port < 1 || port > 65535 {
    return Err("port must be between 1 and 65535")
  }
  if unit_id < 0 || unit_id > 255 {
    return Err("unit ID must be between 0 and 255")
  }
  let mut address = 0
  let mut count = 0
  let mut bases = [0, 40000, 50000]
  if command == "sunspec" {
    if positional.length() == 4 {
      let base = match integer(positional[3], "base address") {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      if base < 0 || base > 65532 {
        return Err("base address must be between 0 and 65532")
      }
      bases = [base]
    }
  } else {
    address = match integer(positional[3], "address") {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    count = match integer(positional[4], "count") {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    if address < 0 ||
      address > 65535 ||
      count < 1 ||
      count > 125 ||
      address + count > 65536 {
      return Err(
        "register read must contain 1..125 registers within addresses 0..65535",
      )
    }
  }
  Ok(
    Some({
      command,
      host,
      port,
      unit_id,
      address,
      count,
      bases,
      model_address,
      timeout_ms,
      json,
    }),
  )
}
