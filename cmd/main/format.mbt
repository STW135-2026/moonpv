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

///|
/// None is a map-only result. A snapshot is formatted only after every read succeeds.
fn format_device(
  device : @moonpv.SunSpecDevice,
  snapshots : Array[Snapshot]?,
  json~ : Bool,
) -> String {
  if json {
    let models = device.models.map(model => {
      let entry : Map[String, Json] = {
        "id": @json.to_json(model.id),
        "address": @json.to_json(model.start_address),
        "length": @json.to_json(model.length),
      }
      if snapshots is None {
        entry["snapshot_supported"] = @json.to_json(model.supports_snapshot())
      }
      Json::object(entry)
    })
    let fields : Map[String, Json] = {
      "schema_version": 1,
      "base_address": @json.to_json(device.base_address),
      "models": @json.to_json(models),
    }
    if snapshots is Some(readings) {
      fields["snapshots"] = @json.to_json(readings.map(snapshot_json))
    }
    return Json::object(fields).stringify(indent=2)
  }
  let lines = ["SunSpec base address: \{device.base_address}"]
  for model in device.models {
    let description = "Model \{model.id}: address \{model.start_address}, length \{model.length}"
    if snapshots is None {
      let support = if model.supports_snapshot() {
        "supported"
      } else {
        "unsupported"
      }
      lines.push(description + ", snapshot: " + support)
    } else {
      lines.push(description)
    }
  }
  if snapshots is Some(readings) {
    for snapshot in readings {
      lines.push("Model \{snapshot.id} at \{snapshot.address}:")
      for point in snapshot.points {
        let value = match point.value {
          Some(value) => value
          None => point.status
        }
        lines.push("  \{point.name}: \{value} \{point.unit}")
      }
    }
  } else if device.models.is_empty() {
    lines.push("No models advertised")
  }
  lines.join("\n")
}
