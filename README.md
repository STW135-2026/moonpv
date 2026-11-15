# MoonPV

MoonPV 是一个用 MoonBit 写的 SunSpec Modbus TCP 设备读取库和命令行工具。它可以查找设备的 SunSpec 地址、列出设备公布的模型，并读取三相逆变器 Model 103 与三相电表 Model 203 的常用数据。

它面向需要把光伏逆变器接入 MoonBit 服务、边缘网关或本地监测程序的开发者。设备仍使用自己的 Modbus TCP 地址和 Unit ID；工具只读取数据，不下发控制指令。

## 当前功能

- 在用户指定的地址，或常见地址 `0`、`40000`、`50000` 查找 SunSpec 标记。
- 按设备公布的模型 ID 和长度遍历模型链；设备插入可选模型时，后续模型地址仍按实际长度定位。
- 读取三相逆变器 Model 103 的相电压、有功功率和频率。
- 读取三相电表 Model 203 的相电压、有功功率、频率，以及累计输入/输出电量。
- 保留原始数值和 SunSpec 十进制缩放因子；正确识别标准的未实现值。
- 检查模型边界、模型长度和响应头；对设备未实现的标准数值点作标记。
- 提供 MoonBit API 和 native 命令行工具。

当前版本暂不解析 Model 1 厂商/序列号字符串、Model 203 的全部 105 个数据点、厂商扩展模型、Modbus RTU 或写入控制点。

## 运行

需要 MoonBit 工具链。项目目标为 native，网络 I/O 使用官方 `moonbitlang/async` TCP socket。

```sh
moon check --target native
moon test --target native
moon build --target native --release
```

连接 Unit ID 为 1 的设备，自动查找常见 SunSpec 基地址：

```sh
moon run cmd/main -- sunspec 192.168.1.20 502 1
```

如果设备手册给出明确的 SunSpec PDU 基地址，可以只探测该地址：

```sh
moon run cmd/main -- sunspec 192.168.1.20 502 1 40000
```

也可用原始寄存器命令核对设备数据：

```sh
moon run cmd/main -- read-holding 192.168.1.20 502 1 40000 4
```

## 在 MoonBit 程序中调用

完整的可编译用法见 [`examples/sunspec_inverter/main.mbt`](examples/sunspec_inverter/main.mbt)：

```moonbit
let client = match @moonpv.Client::connect(
  "192.168.1.20",
  502,
  unit_id=1,
) {
  Ok(client) => client
  Err(message) => fail(message)
}
defer client.close()

let device = match client.discover_sunspec([0, 40000, 50000]) {
  Ok(device) => device
  Err(message) => fail(message)
}
let inverter = client.read_inverter_103(device)
```

返回的功率、电压和频率是原始整数及其缩放因子。例如 `1234`、缩放因子 `-1` 表示 `123.4` 个对应单位；保留原值便于上层选择小数或定点数格式。

## 项目价值

SunSpec 为兼容设备定义了统一的数据模型，常用于光伏逆变器和电力设备。MoonPV 把“找设备模型、定位寄存器、应用缩放因子”封装成 MoonBit API，MoonBit 网关或监测服务可复用同一套接入代码。Model 203 的输入/输出累计电量也便于本地能量监测程序判断电网取电和送电情况，不必为每个品牌手工硬编码寄存器偏移。

本项目按 SunSpec Alliance 发布的设备信息规范和模型定义实现；项目不声称发明新的通信标准，也不替代设备厂商手册。当前支持范围以公开的 SunSpec 模型 103、203 中已实现的字段为准。

## 参考资料

- [SunSpec Device Information Model Specification](https://sunspec.org/specifications/)
- [SunSpec 官方模型定义仓库](https://github.com/sunspec/models)，包括 [Model 103 三相逆变器定义](https://github.com/sunspec/models/blob/master/json/model_103.json) 和 [Model 203 三相电表定义](https://github.com/sunspec/models/blob/master/json/model_203.json)
- [差异化检索记录](docs/DIFFERENTIATION.zh-CN.md)
