///|
struct Point {
  name : String
  raw : Int64?
  sf : Int32?
  value : String?
  unit : String
  status : String
}

///|
struct Snapshot {
  id : Int32
  address : Int32
  points : Array[Point]
}

///|
fn scaled_point(
  name : String,
  raw : Int64?,
  sf : Int32?,
  unit : String,
) -> Point {
  let (value, status) = match (raw, sf) {
    (None, _) => (None, "not_implemented")
    (Some(_), None) => (None, "scale_unavailable")
    (Some(raw), Some(sf)) =>
      match @moonpv.scaled_decimal(raw, sf) {
        Ok(value) => (Some(value), "ok")
        Err(_) => (None, "invalid_scale")
      }
  }
  { name, raw, sf, value, unit, status, }
}

///|
fn point(name : String, raw : Int32?, sf : Int32?, unit : String) -> Point {
  scaled_point(name, raw.map(value => value.to_int64()), sf, unit)
}

///|
fn energy_point(
  name : String,
  reading : @moonpv.EnergyReading,
  sf : Int32?,
) -> Point {
  match reading {
    NotAccumulated =>
      {
        name,
        raw: Some(0L),
        sf,
        value: None,
        unit: "Wh",
        status: "not_accumulated",
      }
    Accumulated(raw) => scaled_point(name, Some(raw), sf, "Wh")
  }
}

///|
fn inverter_snapshot(
  address : Int32,
  value : @moonpv.Inverter103Snapshot,
) -> Snapshot {
  {
    id: 103,
    address,
    points: [
      point("voltage_a", value.phase_voltage_a, value.voltage_scale_factor, "V"),
      point("voltage_b", value.phase_voltage_b, value.voltage_scale_factor, "V"),
      point("voltage_c", value.phase_voltage_c, value.voltage_scale_factor, "V"),
      point(
        "active_power",
        value.active_power,
        value.active_power_scale_factor,
        "W",
      ),
      point("frequency", value.frequency, value.frequency_scale_factor, "Hz"),
    ],
  }
}

///|
fn meter_snapshot(
  address : Int32,
  value : @moonpv.Meter203Snapshot,
) -> Snapshot {
  {
    id: 203,
    address,
    points: [
      point("voltage_a", value.phase_voltage_a, value.voltage_scale_factor, "V"),
      point("voltage_b", value.phase_voltage_b, value.voltage_scale_factor, "V"),
      point("voltage_c", value.phase_voltage_c, value.voltage_scale_factor, "V"),
      point(
        "active_power",
        value.active_power,
        value.active_power_scale_factor,
        "W",
      ),
      point("frequency", value.frequency, value.frequency_scale_factor, "Hz"),
      energy_point(
        "imported_energy",
        value.imported_energy,
        value.energy_scale_factor,
      ),
      energy_point(
        "exported_energy",
        value.exported_energy,
        value.energy_scale_factor,
      ),
    ],
  }
}

///|
fn snapshot_json(snapshot : Snapshot) -> Json {
  let points : Map[String, Json] = Map([])
  for point in snapshot.points {
    points[point.name] = {
      // Current raw fields are at most 32 bits, exactly representable as JSON
      // numbers. Do not use generic Option/Int64 encoding (array/string).
      "raw": match point.raw {
        None => @json.null
        Some(value) => Json::number(value.to_double())
      },
      "scale_factor": match point.sf {
        None => @json.null
        Some(value) => @json.to_json(value)
      },
      "value": match point.value {
        None => @json.null
        Some(value) => @json.to_json(value)
      },
      "unit": @json.to_json(point.unit),
      "status": @json.to_json(point.status),
    }
  }
  {
    "model_id": @json.to_json(snapshot.id),
    "address": @json.to_json(snapshot.address),
    "points": @json.to_json(points),
  }
}
