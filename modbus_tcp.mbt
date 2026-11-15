///|
/// An open Modbus TCP connection. Concurrent calls are serialized so each
/// transaction ID stays paired with its response.
pub struct Client {
  connection : @socket.Tcp
  unit_id : Int32
  transaction_id : @ref.Ref[Int32]
  transaction_mutex : @async.Mutex
}

///|
/// Connect to a Modbus TCP server. Unit ID defaults to 1.
pub async fn Client::connect(
  host : String,
  port : Int32,
  unit_id~ : Int32 = 1,
) -> Result[Client, String] {
  if port < 1 || port > 65535 {
    return Err("port must be between 1 and 65535")
  }
  if unit_id < 0 || unit_id > 255 {
    return Err("unit ID must be between 0 and 255")
  }
  try {
    let connection = @socket.Tcp::connect_to_host(
      host,
      port~,
      protocol=@socket.OnlyV4,
    )
    Ok({
      connection,
      unit_id,
      transaction_id: @ref.Ref(1),
      transaction_mutex: @async.Mutex::Mutex(),
    })
  } catch {
    _ => Err("could not connect to " + host + ":" + port.to_string())
  }
}

///|
/// Close the underlying TCP connection.
pub fn Client::close(self : Client) -> Unit {
  self.connection.close()
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
  self.transaction_mutex.acquire()
  defer self.transaction_mutex.release()
  let transaction_id = self.transaction_id.val
  self.transaction_id.val = (transaction_id + 1) & 0xFFFF
  let request_adu = encode_adu(transaction_id, self.unit_id, request_pdu)
  try {
    self.connection.write(Bytes::from_array(request_adu))
    let header_bytes = self.connection.read_exactly(7)
    let header = bytes_to_array(header_bytes)
    let length = read_u16(header, 4)
    if length < 2 || length > 254 {
      return Err("response MBAP length is outside 2..254")
    }
    let remaining = self.connection.read_exactly(length - 1)
    let adu = header
    for byte in bytes_to_array(remaining) {
      adu.push(byte)
    }
    decode_response(adu, transaction_id, self.unit_id, function_code)
  } catch {
    _ => Err("TCP exchange failed or the peer closed the connection")
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
