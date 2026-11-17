///|
/// A model block advertised by a SunSpec device. Addresses are Modbus PDU
/// addresses (zero-based), as sent on the wire.
pub struct SunSpecModel {
  id : Int32
  start_address : Int32
  length : Int32
}

///|
/// A SunSpec device map found at a holding-register base address.
pub struct SunSpecDevice {
  base_address : Int32
  models : Array[SunSpecModel]
}

///|
/// The commonly used live points from SunSpec three-phase inverter Model 103.
/// Values remain raw integers with their scale factors so no precision is lost.
pub struct Inverter103Snapshot {
  phase_voltage_a : Int32?
  phase_voltage_b : Int32?
  phase_voltage_c : Int32?
  voltage_scale_factor : Int32?
  active_power : Int32?
  active_power_scale_factor : Int32?
  frequency : Int32?
  frequency_scale_factor : Int32?
}

///|
/// Live and accumulated points from SunSpec three-phase meter Model 203.
pub struct Meter203Snapshot {
  phase_voltage_a : Int32?
  phase_voltage_b : Int32?
  phase_voltage_c : Int32?
  voltage_scale_factor : Int32?
  active_power : Int32?
  active_power_scale_factor : Int32?
  frequency : Int32?
  frequency_scale_factor : Int32?
  imported_energy : EnergyReading
  exported_energy : EnergyReading
  energy_scale_factor : Int32?
}

///|
/// SunSpec acc32 reserves zero for NOT ACCUMULATED. Unlike uint32,
/// 0xFFFFFFFF is a valid accumulated value, not an unavailable sentinel.
#derive(Eq, Debug)
pub(all) enum EnergyReading {
  NotAccumulated
  Accumulated(Int64)
}

///|
/// Find the SunSpec map at one of the supplied holding-register addresses.
/// Common bases are 0, 40000 and 50000; pass only the device's documented base
/// to avoid probing registers unnecessarily.
pub async fn Client::discover_sunspec(
  self : Client,
  candidates : Array[Int32],
) -> Result[SunSpecDevice, String] {
  if candidates.is_empty() {
    return Err("at least one SunSpec base address is required")
  }
  for base in candidates {
    if base < 0 || base > 65532 {
      return Err("SunSpec base address must be between 0 and 65532")
    }
  }
  let mut last_address_error = ""
  for base in candidates {
    match self.read_holding_registers(base, 2) {
      Ok(marker) =>
        if marker[0] == 0x5375 && marker[1] == 0x6E53 {
          return scan_sunspec_models(self, base)
        }
      Err(message) => {
        // Illegal address is expected when probing the alternative bases.
        // Other device/transport errors must remain visible to the caller.
        if message == "Modbus exception 2 for function 3" {
          last_address_error = "; address \{base}: \{message}"
          continue
        }
        return Err("SunSpec probe at \{base} failed: \{message}")
      }
    }
  }
  Err(
    "SunSpec marker was not found at the supplied base addresses" +
    last_address_error,
  )
}

///|
/// Read and decode the standard live points in a three-phase inverter Model 103.
pub async fn Client::read_inverter_103(
  self : Client,
  device : SunSpecDevice,
  start_address? : Int32,
) -> Result[Inverter103Snapshot, String] {
  let model = match select_model(device, 103, start_address) {
    Ok(model) => model
    Err(message) => return Err(message)
  }
  if model.length != 50 {
    return Err("SunSpec Model 103 requires the standard 50-register layout")
  }
  let values = match
    self.read_holding_registers(model.start_address, model.length + 2) {
    Ok(values) => values
    Err(message) => return Err(message)
  }
  if values[0] != 103 || values[1] != model.length {
    return Err("SunSpec Model 103 header changed after discovery")
  }
  let voltage_sf = match decode_scale_factor(values[13]) {
    Ok(sf) => sf
    Err(message) => return Err("Model 103 voltage: " + message)
  }
  let power_sf = match decode_scale_factor(values[15]) {
    Ok(sf) => sf
    Err(message) => return Err("Model 103 power: " + message)
  }
  let frequency_sf = match decode_scale_factor(values[17]) {
    Ok(sf) => sf
    Err(message) => return Err("Model 103 frequency: " + message)
  }
  return Ok({
    phase_voltage_a: sunspec_u16(values[10]),
    phase_voltage_b: sunspec_u16(values[11]),
    phase_voltage_c: sunspec_u16(values[12]),
    voltage_scale_factor: voltage_sf,
    active_power: sunspec_i16_option(values[14]),
    active_power_scale_factor: power_sf,
    frequency: sunspec_u16(values[16]),
    frequency_scale_factor: frequency_sf,
  })
}

///|
/// Read selected live and accumulated points from SunSpec three-phase Meter Model 203.
pub async fn Client::read_meter_203(
  self : Client,
  device : SunSpecDevice,
  start_address? : Int32,
) -> Result[Meter203Snapshot, String] {
  let model = match select_model(device, 203, start_address) {
    Ok(model) => model
    Err(message) => return Err(message)
  }
  if model.length != 105 {
    return Err("SunSpec Model 203 requires the standard 105-register layout")
  }
  let values = match
    self.read_holding_registers(model.start_address, model.length + 2) {
    Ok(values) => values
    Err(message) => return Err(message)
  }
  if values[0] != 203 || values[1] != model.length {
    return Err("SunSpec Model 203 header changed after discovery")
  }
  let voltage_sf = match decode_scale_factor(values[15]) {
    Ok(sf) => sf
    Err(message) => return Err("Model 203 voltage: " + message)
  }
  let power_sf = match decode_scale_factor(values[22]) {
    Ok(sf) => sf
    Err(message) => return Err("Model 203 power: " + message)
  }
  let frequency_sf = match decode_scale_factor(values[17]) {
    Ok(sf) => sf
    Err(message) => return Err("Model 203 frequency: " + message)
  }
  let energy_sf = match decode_scale_factor(values[54]) {
    Ok(sf) => sf
    Err(message) => return Err("Model 203 energy: " + message)
  }
  return Ok({
    phase_voltage_a: sunspec_i16_option(values[8]),
    phase_voltage_b: sunspec_i16_option(values[9]),
    phase_voltage_c: sunspec_i16_option(values[10]),
    voltage_scale_factor: voltage_sf,
    frequency: sunspec_i16_option(values[16]),
    frequency_scale_factor: frequency_sf,
    active_power: sunspec_i16_option(values[18]),
    active_power_scale_factor: power_sf,
    exported_energy: sunspec_acc32(values[38], values[39]),
    imported_energy: sunspec_acc32(values[46], values[47]),
    energy_scale_factor: energy_sf,
  })
}

///|
fn select_model(
  device : SunSpecDevice,
  id : Int32,
  address : Int32?,
) -> Result[SunSpecModel, String] {
  let matches = device.models.filter(model => {
    model.id == id &&
    (match address {
      None => true
      Some(value) => model.start_address == value
    })
  })
  match matches.length() {
    0 => Err("SunSpec Model \{id} was not found at the requested address")
    1 => Ok(matches[0])
    _ => Err("multiple Model \{id} instances found; specify start_address")
  }
}

///|
async fn scan_sunspec_models(
  client : Client,
  base : Int32,
) -> Result[SunSpecDevice, String] {
  let mut address = base + 2
  let models : Array[SunSpecModel] = []
  // Allow 64 data models plus the final two-register end marker.
  for _ in 0..<65 {
    if address > 65534 {
      return Err("SunSpec model chain runs beyond the Modbus address space")
    }
    let header = match client.read_holding_registers(address, 2) {
      Ok(header) => header
      Err(message) =>
        return Err("could not read SunSpec model header: " + message)
    }
    let id = header[0]
    let length = header[1]
    if id == 0xFFFF {
      if length != 0 {
        return Err("SunSpec end model must have length zero")
      }
      return Ok({ base_address: base, models, })
    }
    if models.length() == 64 {
      return Err("SunSpec model chain exceeded the 64-model safety limit")
    }
    if length < 1 || address + length + 2 > 65536 {
      return Err("SunSpec model has an invalid length or address range")
    }
    models.push({ id, start_address: address, length, })
    address = address + length + 2
  }
  Err("SunSpec model chain exceeded the 64-model safety limit")
}

///|
fn sunspec_u16(value : Int32) -> Int32? {
  if value == 0xFFFF {
    None
  } else {
    Some(value)
  }
}

///|
fn sunspec_i16(value : Int32) -> Int32 {
  if value >= 0x8000 {
    value - 65536
  } else {
    value
  }
}

///|
fn sunspec_i16_option(value : Int32) -> Int32? {
  if value == 0x8000 {
    None
  } else {
    Some(sunspec_i16(value))
  }
}

///|
fn sunspec_acc32(high : Int32, low : Int32) -> EnergyReading {
  if high == 0 && low == 0 {
    NotAccumulated
  } else {
    Accumulated((high.to_int64() << 16) | low.to_int64())
  }
}

///|
fn decode_scale_factor(value : Int32) -> Result[Int32?, String] {
  match sunspec_i16_option(value) {
    Some(sf) if sf < -10 || sf > 10 =>
      Err("SunSpec scale factor must be in -10..10 or unavailable")
    sf => Ok(sf)
  }
}

///|
/// Convert a raw integer and a valid SunSpec scale factor to exact decimal text.
/// This avoids floating-point rounding, including for 32-bit energy counters.
pub fn scaled_decimal(
  raw : Int64,
  scale_factor : Int32,
) -> Result[String, String] {
  if scale_factor < -10 || scale_factor > 10 {
    return Err("SunSpec scale factor must be in -10..10")
  }
  let text = raw.to_string()
  let negative = raw < 0
  let digits = if negative { text[1:].to_owned() } else { text }
  let sign = if negative { "-" } else { "" }
  if scale_factor >= 0 {
    if raw == 0 {
      return Ok("0")
    }
    let mut result = sign + digits
    for _ in 0..<scale_factor {
      result = result + "0"
    }
    return Ok(result)
  }
  let point = digits.length() + scale_factor
  if point > 0 {
    Ok(sign + digits[:point].to_owned() + "." + digits[point:].to_owned())
  } else {
    let mut result = sign + "0."
    for _ in 0..<-point {
      result = result + "0"
    }
    Ok(result + digits)
  }
}
