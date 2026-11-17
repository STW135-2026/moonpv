///|
extern "c" fn process_exit(code : Int32) = "exit"

///|
async fn main {
  let args = @env.args()
  if args.length() != 4 {
    @stdio.stderr.write(
      "Usage: moon run examples/sunspec_inverter -- <host> <port> <unit>\n",
    )
    process_exit(2)
    return
  }
  let (port, unit_id) = (@string.parse_int(args[2]), @string.parse_int(args[3])) catch {
    _ => {
      @stdio.stderr.write("port and unit must be integers\n")
      process_exit(2)
      return
    }
  }
  match read_sunspec_inverter(args[1], port, unit_id) {
    Err(message) => {
      @stdio.stderr.write(message + "\n")
      process_exit(1)
    }
    Ok(value) => {
      let power = match (value.active_power, value.active_power_scale_factor) {
        (Some(raw), Some(sf)) =>
          match @moonpv.scaled_decimal(raw.to_int64(), sf) {
            Ok(text) => text + " W"
            Err(message) => message
          }
        _ => "unavailable"
      }
      @stdio.stdout.write("Inverter active power: " + power + "\n")
    }
  }
}

///|
/// Find a SunSpec device and read a three-phase inverter summary.
pub async fn read_sunspec_inverter(
  host : String,
  port : Int32,
  unit_id : Int32,
) -> Result[@moonpv.Inverter103Snapshot, String] {
  let client = match @moonpv.Client::connect(host, port, unit_id~) {
    Ok(client) => client
    Err(message) => return Err(message)
  }
  defer client.close()
  let device = match client.discover_sunspec([0, 40000, 50000]) {
    Ok(device) => device
    Err(message) => return Err(message)
  }
  client.read_inverter_103(device)
}
