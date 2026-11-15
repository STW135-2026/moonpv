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
