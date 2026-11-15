///|
test "MBAP encoding keeps big-endian transaction and length fields" {
  let frame = encode_adu(0x1234, 1, [
    (3).to_byte(),
    (0).to_byte(),
    (10).to_byte(),
    (0).to_byte(),
    (2).to_byte(),
  ])
  assert_eq(frame, [
    (0x12).to_byte(),
    (0x34).to_byte(),
    (0).to_byte(),
    (0).to_byte(),
    (0).to_byte(),
    (6).to_byte(),
    (1).to_byte(),
    (3).to_byte(),
    (0).to_byte(),
    (10).to_byte(),
    (0).to_byte(),
    (2).to_byte(),
  ])
}

///|
test "read register response decodes one complete Modbus TCP frame" {
  let frame : Array[Byte] = [
    (0x12).to_byte(),
    (0x34).to_byte(),
    (0).to_byte(),
    (0).to_byte(),
    (0).to_byte(),
    (7).to_byte(),
    (1).to_byte(),
    (3).to_byte(),
    (4).to_byte(),
    (0).to_byte(),
    (42).to_byte(),
    (1).to_byte(),
    (0).to_byte(),
  ]
  let response = decode_response(frame, 0x1234, 1, 3)
  assert_true(response is Ok(_))
  match response {
    Ok(pdu) =>
      assert_eq(pdu, [
        (3).to_byte(),
        (4).to_byte(),
        (0).to_byte(),
        (42).to_byte(),
        (1).to_byte(),
        (0).to_byte(),
      ])
    Err(_) => fail("expected a valid response")
  }
}

///|
test "Modbus exception response reports its exception code" {
  let frame : Array[Byte] = [
    (0).to_byte(),
    (1).to_byte(),
    (0).to_byte(),
    (0).to_byte(),
    (0).to_byte(),
    (3).to_byte(),
    (1).to_byte(),
    (0x83).to_byte(),
    (2).to_byte(),
  ]
  match decode_response(frame, 1, 1, 3) {
    Err(message) => assert_true(message.contains("exception 2"))
    Ok(_) => fail("expected an exception response")
  }
}

///|
test "response transaction unit protocol function and length are checked" {
  let valid : Array[Byte] = [
    (0).to_byte(),
    (4).to_byte(),
    (0).to_byte(),
    (0).to_byte(),
    (0).to_byte(),
    (3).to_byte(),
    (1).to_byte(),
    (3).to_byte(),
    (2).to_byte(),
    (0).to_byte(),
  ]
  assert_true(decode_response(valid, 5, 1, 3) is Err(_))
  let wrong_protocol = valid.copy()
  wrong_protocol[3] = (1).to_byte()
  assert_true(decode_response(wrong_protocol, 4, 1, 3) is Err(_))
  let wrong_unit = valid.copy()
  wrong_unit[6] = (2).to_byte()
  assert_true(decode_response(wrong_unit, 4, 1, 3) is Err(_))
  let wrong_function = valid.copy()
  wrong_function[7] = (4).to_byte()
  assert_true(decode_response(wrong_function, 4, 1, 3) is Err(_))
  let wrong_length = valid.copy()
  wrong_length[5] = (5).to_byte()
  assert_true(decode_response(wrong_length, 4, 1, 3) is Err(_))
}

///|
test "range checks reject zero quantity and address overflow" {
  assert_false(valid_range(0, 0, 125))
  assert_false(valid_range(65535, 2, 125))
  assert_false(valid_range(-1, 1, 125))
  assert_true(valid_range(65535, 1, 125))
  assert_true(valid_range(0, 125, 125))
}

///|
test "register response values use Modbus network byte order" {
  let pdu : Array[Byte] = [
    (3).to_byte(),
    (4).to_byte(),
    (0x12).to_byte(),
    (0x34).to_byte(),
    (0xAB).to_byte(),
    (0xCD).to_byte(),
  ]
  match decode_register_values(pdu, 2) {
    Ok(values) => assert_eq(values, [0x1234, 0xABCD])
    Err(_) => fail("expected two decoded holding registers")
  }
  assert_true(decode_register_values(pdu, 1) is Err(_))
}

///|
test "coil response bits are unpacked least-significant bit first" {
  let pdu : Array[Byte] = [(1).to_byte(), (1).to_byte(), (0b00000101).to_byte()]
  match decode_bit_values(pdu, 4) {
    Ok(values) => assert_eq(values, [true, false, true, false])
    Err(_) => fail("expected four decoded coils")
  }
  assert_true(decode_bit_values(pdu, 9) is Err(_))
}

///|
test "SunSpec signed values and unimplemented sentinels decode correctly" {
  assert_eq(sunspec_i16(0x0001), 1)
  assert_eq(sunspec_i16(0xFFFF), -1)
  assert_eq(sunspec_i16(0x8000), -32768)
  assert_eq(sunspec_i16_option(0x8000), None)
  assert_eq(sunspec_i16_option(0x7FFF), Some(32767))
  assert_eq(sunspec_u16(0xFFFF), None)
  assert_eq(sunspec_u16(0xFFFE), Some(0xFFFE))
  assert_eq(sunspec_u32(0xFFFF, 0xFFFF), None)
  assert_eq(sunspec_u32(0x1234, 0x5678), Some(305419896))
}

///|
async test "SunSpec discovery follows model lengths and reads Model 103 points" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let port = server.addr.port()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      let (connection, _) = server.accept()
      for _ in 0..<8 {
        let header = bytes_to_array(connection.read_exactly(7))
        let transaction_id = read_u16(header, 0)
        let unit_id = byte_at(header, 6)
        let length = read_u16(header, 4)
        let request = bytes_to_array(connection.read_exactly(length - 1))
        let address = read_u16(request, 1)
        let quantity = read_u16(request, 3)
        let values : Array[Int32] = if address == 0 {
          [0, 0]
        } else if address == 40000 {
          [0x5375, 0x6E53]
        } else if address == 40002 && quantity == 2 {
          [1, 66]
        } else if address == 40070 && quantity == 2 {
          [103, 50]
        } else if address == 40122 && quantity == 2 {
          [203, 105]
        } else if address == 40229 {
          [0xFFFF, 0]
        } else if address == 40070 && quantity == 52 {
          let data = Array::make(52, 0)
          data[0] = 103
          data[1] = 50
          data[10] = 2300
          data[11] = 2310
          data[12] = 2290
          data[13] = 0xFFFF
          data[14] = 1234
          data[15] = 0xFFFF
          data[16] = 5000
          data[17] = 0xFFFF
          data
        } else {
          let data = Array::make(107, 0)
          data[0] = 203
          data[1] = 105
          data[8] = 2315
          data[15] = 0xFFFF
          data[16] = 5000
          data[17] = 0xFFFF
          data[18] = 5000
          data[22] = 0xFFFE
          data[39] = 12000
          data[47] = 25000
          data[54] = 0
          data
        }
        let response_pdu : Array[Byte] = [
          (3).to_byte(),
          (values.length() * 2).to_byte(),
        ]
        for value in values {
          response_pdu.push(high_byte(value))
          response_pdu.push(low_byte(value))
        }
        connection.write(
          Bytes::from_array(encode_adu(transaction_id, unit_id, response_pdu)),
        )
      }
      connection.close()
    }
    let client = match Client::connect("127.0.0.1", port, unit_id=1) {
      Ok(client) => client
      Err(_) => fail("could not connect to the local SunSpec test server")
    }
    let device = match client.discover_sunspec([0, 40000]) {
      Ok(device) => device
      Err(message) => fail("SunSpec discovery failed: " + message)
    }
    assert_eq(device.base_address, 40000)
    assert_eq(device.models.length(), 3)
    assert_eq(device.models[0].id, 1)
    assert_eq(device.models[0].start_address, 40002)
    assert_eq(device.models[1].id, 103)
    assert_eq(device.models[1].start_address, 40070)
    assert_eq(device.models[1].length, 50)
    let snapshot = match client.read_inverter_103(device) {
      Ok(snapshot) => snapshot
      Err(message) => fail("Model 103 read failed: " + message)
    }
    assert_eq(snapshot.phase_voltage_a, Some(2300))
    assert_eq(snapshot.phase_voltage_c, Some(2290))
    assert_eq(snapshot.voltage_scale_factor, Some(-1))
    assert_eq(snapshot.active_power, Some(1234))
    assert_eq(snapshot.active_power_scale_factor, Some(-1))
    assert_eq(snapshot.frequency, Some(5000))
    assert_eq(snapshot.frequency_scale_factor, Some(-1))
    assert_eq(device.models[2].id, 203)
    assert_eq(device.models[2].start_address, 40122)
    assert_eq(device.models[2].length, 105)
    let meter = match client.read_meter_203(device) {
      Ok(meter) => meter
      Err(message) => fail("Model 203 read failed: " + message)
    }
    assert_eq(meter.phase_voltage_a, Some(2315))
    assert_eq(meter.voltage_scale_factor, Some(-1))
    assert_eq(meter.active_power, Some(5000))
    assert_eq(meter.active_power_scale_factor, Some(-2))
    assert_eq(meter.frequency, Some(5000))
    assert_eq(meter.frequency_scale_factor, Some(-1))
    assert_eq(meter.imported_energy, Some(25000))
    assert_eq(meter.exported_energy, Some(12000))
    assert_eq(meter.energy_scale_factor, Some(0))
    client.close()
  }
}

///|
async test "client serializes concurrent requests on one TCP connection" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let port = server.addr.port()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      let (connection, _) = server.accept()
      for _ in 0..<2 {
        let header = bytes_to_array(connection.read_exactly(7))
        let length = read_u16(header, 4)
        let request_pdu = bytes_to_array(connection.read_exactly(length - 1))
        let address = read_u16(request_pdu, 1)
        let value = if address == 10 { 111 } else { 222 }
        let response_pdu : Array[Byte] = [
          (3).to_byte(),
          (2).to_byte(),
          high_byte(value),
          low_byte(value),
        ]
        let response = encode_adu(
          read_u16(header, 0),
          byte_at(header, 6),
          response_pdu,
        )
        connection.write(Bytes::from_array(response))
      }
      connection.close()
    }
    let client = match Client::connect("127.0.0.1", port, unit_id=1) {
      Ok(client) => client
      Err(_) => fail("could not connect to the local Modbus test server")
    }
    let first = group.spawn() <| () => { client.read_holding_registers(10, 1) }
    let second = group.spawn() <| () => { client.read_holding_registers(20, 1) }
    let first_result = first.wait()
    let second_result = second.wait()
    client.close()
    match first_result {
      Ok(values) => assert_eq(values, [111])
      Err(_) => fail("first concurrent request failed")
    }
    match second_result {
      Ok(values) => assert_eq(values, [222])
      Err(_) => fail("second concurrent request failed")
    }
  }
}
