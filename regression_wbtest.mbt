///|
test "SunSpec scaling validates the exact signed range" {
  assert_eq(decode_scale_factor(0x8000), Ok(None))
  assert_eq(decode_scale_factor(0xFFF6), Ok(Some(-10)))
  assert_eq(decode_scale_factor(10), Ok(Some(10)))
  assert_true(decode_scale_factor(11) is Err(_))
  assert_true(decode_scale_factor(0xFFF5) is Err(_))
  assert_true(decode_scale_factor(0x7FFF) is Err(_))
}

///|
test "exact decimal values preserve energy precision and sign" {
  assert_eq(scaled_decimal(2300L, -1), Ok("230.0"))
  assert_eq(scaled_decimal(-123L, -2), Ok("-1.23"))
  assert_eq(scaled_decimal(1L, -10), Ok("0.0000000001"))
  assert_eq(scaled_decimal(4294967295L, -3), Ok("4294967.295"))
  assert_eq(scaled_decimal(4294967295L, 10), Ok("42949672950000000000"))
  assert_eq(scaled_decimal(0L, -1), Ok("0.0"))
  assert_eq(scaled_decimal(0L, 10), Ok("0"))
  assert_eq(
    scaled_decimal(-9223372036854775808L, -1),
    Ok("-922337203685477580.8"),
  )
  assert_true(scaled_decimal(1L, 11) is Err(_))
}

///|
async test "library rejects invalid connection parameters without IO" {
  assert_true(Client::connect("", 502) is Err(_))
  assert_true(Client::connect("localhost", 0) is Err(_))
  assert_true(Client::connect("localhost", 502, unit_id=256) is Err(_))
  assert_true(Client::connect("localhost", 502, timeout_ms=0) is Err(_))
}

///|
async test "cancelling a queued caller leaves the active exchange usable" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_timeout(4000, () => {
    @async.with_task_group() <| group => {
      group.spawn_bg() <| () => {
        let (connection, _) = server.accept()
        defer connection.close()
        for index in 0..<2 {
          let request = bytes_to_array(connection.read_exactly(12))
          if index == 0 {
            @async.sleep(200)
          }
          let pdu : Array[Byte] = [b'\x03', b'\x02', b'\x00', b'\x2a']
          connection.write(
            Bytes::from_array(encode_adu(read_u16(request, 0), 1, pdu)),
          )
        }
      }
      let client = match
        Client::connect("127.0.0.1", server.addr.port(), timeout_ms=2000) {
        Ok(client) => client
        Err(message) => fail(message)
      }
      defer client.close()
      let first = group.spawn(() => client.read_holding_registers(0, 1))
      @async.sleep(30)
      let cancelled = @async.with_timeout_opt(50, () => {
        client.read_holding_registers(1, 1)
      })
      assert_true(cancelled is None)
      assert_false(client.is_closed())
      assert_eq(first.wait(), Ok([42]))
      assert_eq(client.read_holding_registers(2, 1), Ok([42]))
    }
  })
}

///|
test "multiple meter models require explicit selection" {
  let device : SunSpecDevice = {
    base_address: 0,
    models: [
      { id: 203, start_address: 70, length: 105, },
      { id: 203, start_address: 177, length: 105, },
    ],
  }
  assert_true(select_model(device, 203, None) is Err(_))
  match select_model(device, 203, Some(177)) {
    Ok(model) => assert_eq(model.start_address, 177)
    Err(message) => fail(message)
  }
  assert_true(select_model(device, 203, Some(100)) is Err(_))
}

///|
async test "silent peer times out and cannot poison a later transaction" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_timeout(3000, () => {
    @async.with_task_group() <| group => {
      group.spawn_bg(no_wait=true) <| () => {
        let (connection, _) = server.accept()
        defer connection.close()
        connection.read_exactly(12) |> ignore
        @async.sleep(10000)
      }
      let client = match
        Client::connect("127.0.0.1", server.addr.port(), timeout_ms=100) {
        Ok(client) => client
        Err(message) => fail(message)
      }
      defer client.close()
      match client.read_holding_registers(0, 2) {
        Err(message) => assert_true(message.contains("timed out"))
        Ok(_) => fail("silent server must not succeed")
      }
      assert_true(client.is_closed())
      match client.read_holding_registers(0, 2) {
        Err(message) => assert_true(message.contains("closed"))
        Ok(_) => fail("timed-out socket must not be reused")
      }
      client.close()
      client.close()
    }
  })
}

///|
async test "malformed MBAP closes the socket before unread bytes are reused" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_timeout(3000, () => {
    @async.with_task_group() <| group => {
      group.spawn_bg(no_wait=true) <| () => {
        let (connection, _) = server.accept()
        defer connection.close()
        connection.read_exactly(12) |> ignore
        connection.write(
          b"\x00\x01\x00\x00\x00\xff\x01junk that must never become another header",
        )
        @async.sleep(10000)
      }
      let client = match Client::connect("127.0.0.1", server.addr.port()) {
        Ok(client) => client
        Err(message) => fail(message)
      }
      defer client.close()
      assert_true(client.read_holding_registers(0, 2) is Err(_))
      assert_true(client.is_closed())
      assert_true(client.read_holding_registers(0, 2) is Err(_))
    }
  })
}

///|
async test "external cancellation closes an in-flight exchange" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      let (connection, _) = server.accept()
      defer connection.close()
      connection.read_exactly(12) |> ignore
      @async.sleep(10000)
    }
    let client = match
      Client::connect("127.0.0.1", server.addr.port(), timeout_ms=2000) {
      Ok(client) => client
      Err(message) => fail(message)
    }
    defer client.close()
    let result = @async.with_timeout_opt(100, () => {
      client.read_holding_registers(0, 2)
    })
    assert_true(result is None)
    assert_true(client.is_closed())
  }
}
