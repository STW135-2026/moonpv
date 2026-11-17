///|
/// An open Modbus TCP connection. Concurrent calls are serialized so each
/// transaction ID stays paired with its response.
pub struct Client {
  priv connection : @socket.Tcp
  priv unit_id : Int32
  priv transaction_id : @ref.Ref[Int32]
  priv transaction_mutex : @async.Mutex
  priv timeout_ms : Int32
  priv closed : @ref.Ref[Bool]
}

///|
/// Connect to a Modbus TCP server. Unit ID defaults to 1.
pub async fn Client::connect(
  host : String,
  port : Int32,
  unit_id~ : Int32 = 1,
  timeout_ms~ : Int32 = 3000,
) -> Result[Client, String] {
  if host.is_empty() {
    return Err("host must not be empty")
  }
  if port < 1 || port > 65535 {
    return Err("port must be between 1 and 65535")
  }
  if unit_id < 0 || unit_id > 255 {
    return Err("unit ID must be between 0 and 255")
  }
  if timeout_ms < 1 || timeout_ms > 600000 {
    return Err("timeout must be between 1 and 600000 milliseconds")
  }
  try {
    let connection = match
      @async.with_timeout_opt(timeout_ms, () => {
        @socket.Tcp::connect_to_host(host, port~)
      }) {
      Some(connection) => connection
      None => return Err("connection timed out after \{timeout_ms} ms")
    }
    Ok({
      connection,
      unit_id,
      transaction_id: @ref.Ref(1),
      transaction_mutex: @async.Mutex::Mutex(),
      timeout_ms,
      closed: @ref.Ref(false),
    })
  } catch {
    error => Err("could not connect to \{host}:\{port}: \{error}")
  }
}

///|
/// Close the underlying TCP connection.
pub fn Client::close(self : Client) -> Unit {
  if !self.closed.val {
    self.closed.val = true
    self.connection.close()
  }
}

///|
/// A timed-out, cancelled, or malformed exchange closes the connection.
/// Connect again before retrying. Calling close repeatedly is safe.
pub fn Client::is_closed(self : Client) -> Bool {
  self.closed.val
}

///|
/// Read coils (function code 1). Coil bits are returned in address order.
pub async fn Client::read_coils(
  self : Client,
  start : Int32,
  quantity : Int32,
) -> Result[Array[Bool], String] {
  self.read_bits(1, start, quantity)
}

///|
/// Read discrete inputs (function code 2).
pub async fn Client::read_discrete_inputs(
  self : Client,
  start : Int32,
  quantity : Int32,
) -> Result[Array[Bool], String] {
  self.read_bits(2, start, quantity)
}

///|
/// Read holding registers (function code 3).
pub async fn Client::read_holding_registers(
  self : Client,
  start : Int32,
  quantity : Int32,
) -> Result[Array[Int32], String] {
  self.read_registers(3, start, quantity)
}

///|
/// Read input registers (function code 4).
pub async fn Client::read_input_registers(
  self : Client,
  start : Int32,
  quantity : Int32,
) -> Result[Array[Int32], String] {
  self.read_registers(4, start, quantity)
}

///|
async fn Client::read_bits(
  self : Client,
  function_code : Int32,
  start : Int32,
  quantity : Int32,
) -> Result[Array[Bool], String] {
  if !valid_range(start, quantity, 2000) {
    return Err("bit read range must contain 1 to 2000 valid addresses")
  }
  let request = make_range_request(function_code, start, quantity)
  match self.transact(function_code, request) {
    Err(message) => Err(message)
    Ok(response) => decode_bit_values(response, quantity)
  }
}

///|
async fn Client::read_registers(
  self : Client,
  function_code : Int32,
  start : Int32,
  quantity : Int32,
) -> Result[Array[Int32], String] {
  if !valid_range(start, quantity, 125) {
    return Err("register read range must contain 1 to 125 valid addresses")
  }
  let request = make_range_request(function_code, start, quantity)
  match self.transact(function_code, request) {
    Err(message) => Err(message)
    Ok(response) => decode_register_values(response, quantity)
  }
}

///|
async fn Client::transact(
  self : Client,
  function_code : Int32,
  request_pdu : Array[Byte],
) -> Result[Array[Byte], String] {
  if self.is_closed() {
    return Err("connection is closed; reconnect before retrying")
  }
  try {
    match
      @async.with_timeout_opt(self.timeout_ms, () => {
        // The deadline also covers waiting behind another caller. A caller that
        // times out in the queue must not close someone else's active exchange.
        self.transaction_mutex.acquire()
        let complete = @ref.Ref(false)
        defer {
          if !complete.val {
            self.close()
          }
          self.transaction_mutex.release()
        }
        if self.is_closed() {
          return Err("connection is closed; reconnect before retrying")
        }
        let transaction_id = self.transaction_id.val
        self.transaction_id.val = (transaction_id + 1) & 0xFFFF
        let request_adu = encode_adu(transaction_id, self.unit_id, request_pdu)
        self.connection.write(Bytes::from_array(request_adu))
        let header = bytes_to_array(self.connection.read_exactly(7))
        let length = read_u16(header, 4)
        if length < 2 || length > 254 {
          return Err("response MBAP length is outside 2..254")
        }
        if read_u16(header, 0) != transaction_id ||
          read_u16(header, 2) != 0 ||
          byte_at(header, 6) != self.unit_id {
          return Err(
            "response transaction, protocol, or unit ID does not match the request",
          )
        }
        let remaining = self.connection.read_exactly(length - 1)
        let adu = header
        for byte in bytes_to_array(remaining) {
          adu.push(byte)
        }
        let decoded = decode_response(
          adu,
          transaction_id,
          self.unit_id,
          function_code,
        )
        match decoded {
          Ok(pdu) => {
            let quantity = read_u16(request_pdu, 3)
            let expected = if function_code <= 2 {
              (quantity + 7) / 8
            } else {
              quantity * 2
            }
            if pdu.length() != expected + 2 || byte_at(pdu, 1) != expected {
              return Err("read response has an invalid byte count")
            }
            complete.val = true
          }
          Err(_) =>
            // A well-formed Modbus exception is a complete response. Its socket
            // remains usable, unlike malformed frames and interrupted reads.
            complete.val = length == 3 &&
              byte_at(adu, 7) == (function_code | 0x80)
        }
        decoded
      }) {
      Some(result) => result
      None => Err("TCP exchange timed out after \{self.timeout_ms} ms")
    }
  } catch {
    error => Err("TCP exchange failed: \{error}")
  }
}

///|
fn encode_adu(
  transaction_id : Int32,
  unit_id : Int32,
  pdu : Array[Byte],
) -> Array[Byte] {
  let length = pdu.length() + 1
  let adu : Array[Byte] = [
    high_byte(transaction_id),
    low_byte(transaction_id),
    (0).to_byte(),
    (0).to_byte(),
    high_byte(length),
    low_byte(length),
    unit_id.to_byte(),
  ]
  for byte in pdu {
    adu.push(byte)
  }
  adu
}

///|
fn decode_response(
  adu : Array[Byte],
  transaction_id : Int32,
  unit_id : Int32,
  function_code : Int32,
) -> Result[Array[Byte], String] {
  if adu.length() < 9 {
    return Err("response is shorter than an MBAP header and function code")
  }
  if read_u16(adu, 0) != transaction_id {
    return Err("response transaction ID does not match the request")
  }
  if read_u16(adu, 2) != 0 {
    return Err("response protocol ID is not Modbus")
  }
  let length = read_u16(adu, 4)
  if length < 2 || length > 254 || length + 6 != adu.length() {
    return Err("response MBAP length does not match the received frame")
  }
  if byte_at(adu, 6) != unit_id {
    return Err("response unit ID does not match the request")
  }
  let response_pdu = adu[7:].to_owned()
  let response_function = byte_at(response_pdu, 0)
  if response_function == (function_code | 0x80) {
    if response_pdu.length() != 2 {
      return Err("malformed Modbus exception response")
    }
    return Err(
      "Modbus exception " +
      byte_at(response_pdu, 1).to_string() +
      " for function " +
      function_code.to_string(),
    )
  }
  if response_function != function_code {
    return Err("response function code does not match the request")
  }
  Ok(response_pdu)
}

///|
fn make_range_request(
  function_code : Int32,
  start : Int32,
  quantity : Int32,
) -> Array[Byte] {
  [
    function_code.to_byte(),
    high_byte(start),
    low_byte(start),
    high_byte(quantity),
    low_byte(quantity),
  ]
}

///|
fn decode_bit_values(
  response : Array[Byte],
  quantity : Int32,
) -> Result[Array[Bool], String] {
  if response.length() < 2 {
    return Err("short bit-read response")
  }
  let expected_byte_count = (quantity + 7) / 8
  let byte_count = byte_at(response, 1)
  if byte_count != expected_byte_count || response.length() != byte_count + 2 {
    return Err("bit-read response has an invalid byte count")
  }
  let values : Array[Bool] = []
  for index in 0..<quantity {
    let packed = byte_at(response, 2 + index / 8)
    values.push(((packed >> (index % 8)) & 1) != 0)
  }
  Ok(values)
}

///|
fn decode_register_values(
  response : Array[Byte],
  quantity : Int32,
) -> Result[Array[Int32], String] {
  if response.length() < 2 {
    return Err("short register-read response")
  }
  let expected_byte_count = quantity * 2
  let byte_count = byte_at(response, 1)
  if byte_count != expected_byte_count || response.length() != byte_count + 2 {
    return Err("register-read response has an invalid byte count")
  }
  let values : Array[Int32] = []
  for index in 0..<quantity {
    values.push(read_u16(response, 2 + index * 2))
  }
  Ok(values)
}

///|
fn valid_address(value : Int32) -> Bool {
  value >= 0 && value <= 65535
}

///|
fn valid_range(start : Int32, quantity : Int32, maximum : Int32) -> Bool {
  quantity >= 1 &&
  quantity <= maximum &&
  valid_address(start) &&
  start + quantity <= 65536
}

///|
fn high_byte(value : Int32) -> Byte {
  ((value >> 8) & 0xFF).to_byte()
}

///|
fn low_byte(value : Int32) -> Byte {
  (value & 0xFF).to_byte()
}

///|
fn byte_at(bytes : Array[Byte], index : Int32) -> Int32 {
  bytes[index].to_int()
}

///|
fn read_u16(bytes : Array[Byte], index : Int32) -> Int32 {
  (byte_at(bytes, index) << 8) | byte_at(bytes, index + 1)
}

///|
fn bytes_to_array(bytes : Bytes) -> Array[Byte] {
  Array::makei(bytes.length(), index => bytes[index])
}
