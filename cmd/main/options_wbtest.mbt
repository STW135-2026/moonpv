///|
test "arguments are rejected before any network operation" {
  for
    args in [
      ["moonpv"],
      ["moonpv", "unknown", "127.0.0.1", "502", "1", "0", "1"],
      ["moonpv", "sunspec", "", "502", "1"],
      ["moonpv", "sunspec", "localhost", "bad", "1"],
      ["moonpv", "sunspec", "localhost", "502", "256"],
      ["moonpv", "sunspec", "localhost", "502", "1", "65533"],
      ["moonpv", "sunspec", "localhost", "502", "1", "--timeout-ms", "0"],
      ["moonpv", "sunspec", "localhost", "502", "1", "--timeout-ms"],
      ["moonpv", "sunspec", "localhost", "502", "1", "--json", "--json"],
      ["moonpv", "read-input", "localhost", "502", "1", "65535", "2"],
      ["moonpv", "read-input", "localhost", "502", "1", "0", "126"],
      [
        "moonpv", "read-input", "localhost", "502", "1", "0", "1", "--model-address",
        "70",
      ],
    ] {
    assert_true(parse_options(args) is Err(_))
  }
}

///|
test "valid options preserve meter selection and timeout" {
  match
    parse_options([
      "moonpv", "sunspec", "localhost", "502", "1", "40000", "--json", "--model-address",
      "40177", "--timeout-ms", "250",
    ]) {
    Ok(Some(options)) => {
      assert_eq(options.bases, [40000])
      assert_eq(options.model_address, Some(40177))
      assert_eq(options.timeout_ms, 250)
      assert_true(options.json)
    }
    _ => fail("expected valid options")
  }
  assert_true(parse_options(["moonpv", "--help"]) is Ok(None))
}
