// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "STW135-2026/moonpv"

version = "0.2.2"

readme = "README.md"

repository = "https://github.com/STW135-2026/moonpv"

license = "Apache-2.0"

keywords = [ "sunspec", "solar", "inverter", "modbus-tcp", "moonbit" ]

preferred_target = "native"

supported_targets = "native"

description = "MoonBit SunSpec reader for solar inverters and meters."

import {
  "moonbitlang/async@0.22.9",
}
