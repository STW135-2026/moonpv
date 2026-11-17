///|
test "JSON fields use numbers strings and null instead of Option array encoding" {
  let actual = snapshot_json({
    id: 203,
    address: 100,
    points: [
      energy_point("max", Accumulated(4294967295L), Some(-3)),
      energy_point("empty", NotAccumulated, Some(0)),
      point("missing", None, Some(0), "V"),
    ],
  })
  let expected : Json = {
    "model_id": 203,
    "address": 100,
    "points": {
      "max": {
        "raw": 4294967295,
        "scale_factor": -3,
        "value": "4294967.295",
        "unit": "Wh",
        "status": "ok",
      },
      "empty": {
        "raw": 0,
        "scale_factor": 0,
        "value": null,
        "unit": "Wh",
        "status": "not_accumulated",
      },
      "missing": {
        "raw": null,
        "scale_factor": 0,
        "value": null,
        "unit": "V",
        "status": "not_implemented",
      },
    },
  }
  assert_eq(actual, expected)
}
