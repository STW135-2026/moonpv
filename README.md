# MoonPV

[![Native checks](https://github.com/STW135-2026/moonpv/actions/workflows/ci.yml/badge.svg)](https://github.com/STW135-2026/moonpv/actions/workflows/ci.yml)

MoonPV 是用 MoonBit 编写的 SunSpec Modbus TCP 读取库和命令行工具。它发现设备公布的模型，读取三相逆变器和电表的常用数据，输出带单位、状态和精确小数的结果。

## 用来做什么

给 MoonBit 网关接入一台支持 SunSpec 的光伏逆变器，通常需要处理 TCP 通信、模型地址、寄存器类型、缩放因子和缺失值。MoonPV 把这些步骤做成可复用 API。采集服务可以直接取得电压、功率、频率和电表累计输入/输出电量；运维脚本也可以读取 CLI 的 JSON，不必另外运行 Python 或 Go 服务。

本项目依据已有标准实现客户端。功能方向与其他语言的 SunSpec 客户端相近，价值是为 MoonBit 提供原生接入能力。[相关项目对比](docs/DIFFERENTIATION.zh-CN.md)列出了已有实现和本项目边界。

## 已实现的范围

| 部分 | 支持内容 |
| --- | --- |
| 设备发现 | 指定基地址或依次探测 `0 / 40000 / 50000`；按 ID、长度遍历模型链，最多 64 个模型 |
| Model 103 | 三相相电压、有功功率、频率；标准布局为 50 个数据寄存器 |
| Model 203 | 三相相电压、有功功率、频率、累计输入/输出电量；标准布局为 105 个数据寄存器 |
| 多实例 | CLI 默认读取所有 103/203 实例，也可按模型地址选择；库遇到同类多实例时要求显式选择 |
| 数值 | 原始整数、缩放因子和精确十进制转换；区分未实现、缺少缩放因子和未累计电量 |
| 连接 | 连接及每次请求默认 3 秒超时；并发请求串行收发；畸形帧、超时或中途取消后关闭连接 |
| 输出 | 文本、JSON、明确的错误退出码；原始 holding/input 寄存器读取命令 |

仅支持 native、Modbus TCP 和上述选定字段。库另有 FC1/2 位读取接口；没有写入指令、RTU、浮点模型、厂商扩展模型、后台轮询、存储或图表功能。Model 1 只参与地址发现，不解析厂商字符串。**尚未在真实逆变器上测试，也没有 SunSpec 认证。**

抓取一次快照时，MoonPV 只读到最后一个需要的测量字段，每个模型发一次请求。在仓库的演示中，读取一台逆变器和两块电表的快照共需 128 个寄存器，v0.2.1 需要 266 个。此数仅统计快照读取，设备发现另计。

## 下载试用

[下载 v0.3.0](https://github.com/STW135-2026/moonpv/releases/tag/v0.3.0)，完整解压后运行 `bin/moonpv --help`（Windows 为 `bin\moonpv.exe`）。直接读取设备无需安装 MoonBit 或 Python；随包的模拟演示需要 Python 3.12+，运行 `python tools/demo.py` 即可。

演示会核对模型发现、读数、未累计电量及 API 示例，成功后显示 `PASS`。[MVP 验收步骤](docs/MVP.zh-CN.md)集中列出了用法、预期结果和验证入口。Windows 包为 x86_64；Linux 包在 Ubuntu 24.04 x86_64 构建和测试，尚未验证其他发行版。

## 从源码运行

工具链固定为 `moonc v0.10.21+06da1ed44`，依赖 `moonbitlang/async@0.22.9`。本机演示和集成测试需要 Python 3.12+，不需要额外 Python 包；参考客户端对照测试另行安装依赖。

以下安装器从官方地址下载固定版本并核对 SHA-256，只写指定的空目录，不修改已有 MoonBit 安装。

Windows PowerShell：

```powershell
python tools/install_toolchain.py .toolchain
$env:MOON_HOME = (Resolve-Path .toolchain).Path
$env:PATH = "$env:MOON_HOME\bin;$env:PATH"
$env:MOON_REGISTRY_API = "1"
python tools/demo.py
```

Linux x86_64：

```sh
python3 tools/install_toolchain.py .toolchain
export MOON_HOME="$PWD/.toolchain"
export PATH="$MOON_HOME/bin:$PATH"
export MOON_REGISTRY_API=1
python3 tools/demo.py
```

已有对应版本时可跳过安装，设置好环境后运行演示。`MOON_REGISTRY_API=1` 使用工具链的 HTTP 包元数据接口，避免依赖旧的本地 Git 包索引。

演示会在 `127.0.0.1` 的随机端口启动模拟设备，读取一台逆变器和两块电表，显示 `4200 W` 逆变器功率、`230.1 V` A 相电压等合成数据，再运行 MoonBit API 示例。退出时关闭服务。这些数值用于验证程序，不代表实机测量。加 `--json` 可输出核对后的完整 JSON。

## 连接设备

设备须启用 SunSpec Modbus TCP。按厂商手册确认主机、端口、Unit ID 和基地址；这里使用线上发送的 **零基 PDU 地址**，不是 `4xxxx` 寄存器编号的通用换算。

先用 `models` 查看这台设备公布的模型。每行列出模型 ID、零基地址、长度和快照支持情况。比如两块电表的模型 ID 都是 203，可以用各自的地址区分。表中标记支持表示 ID 和长度符合解码器要求，实际读数由随后运行的 `sunspec` 返回。加 `--json` 可让脚本按 `snapshot_supported` 筛选。以下命令中的 40122 是示例地址，使用时换成设备列出的值。

```sh
moon run cmd/main -- models 192.168.1.20 502 1 40000
moon run cmd/main -- sunspec 192.168.1.20 502 1 40000 --json
moon run cmd/main -- sunspec 192.168.1.20 502 1 40000 --model-address 40122 --timeout-ms 5000
moon run cmd/main -- read-holding 192.168.1.20 502 1 40000 4
moon run cmd/main -- read-input 192.168.1.20 502 1 0 2 --json
```

`--timeout-ms` 范围为 1–600000，覆盖连接或单次请求（包括等待同一客户端上的其他请求），不是整个发现流程的总时限。连接失效后需要重新连接；工具不会自动重试或静默跳过失败模型。

返回码：`0` 成功、`1` 设备/网络/模型错误、`2` 参数错误。错误只写 stderr；任何选中模型读取失败时，不输出看似成功的部分快照。脚本若需要区分 1 和 2，请直接运行构建产物，避免外层启动工具改变退出码。

JSON 的 `schema_version` 为 1。每个快照包含 `model_id`、模型头 `address` 和 `points`。例如：

```json
{"raw":2301,"scale_factor":-1,"value":"230.1","unit":"V","status":"ok"}
```

`raw` 和 `scale_factor` 是数值或 `null`，`value` 是精确十进制字符串或 `null`。状态为 `ok`、`not_implemented`、`scale_unavailable` 或 `not_accumulated`。SunSpec `acc32` 的零表示“尚未累计”，不当作有效的零电量；`4294967295` 是有效累计值。非法缩放因子会使命令失败。累计电量不是区间用电量，使用方还需处理采样间隔、计数器复位和安装方向。

## 作为 MoonBit 库使用

可执行示例见 [examples/sunspec_inverter/main.mbt](examples/sunspec_inverter/main.mbt)，在 async 上下文中依次调用：

```moonbit
let client = match @moonpv.Client::connect(host, port, unit_id=1, timeout_ms=3000) {
  Ok(client) => client
  Err(message) => return Err(message)
}
defer client.close()
let device = match client.discover_sunspec([40000]) {
  Ok(device) => device
  Err(message) => return Err(message)
}
client.read_inverter_103(device)
```

同一设备有多块电表时传入 `read_meter_203(device, start_address=...)`。API 保留原始整数与缩放因子，可用 `scaled_decimal(raw, sf)` 转为精确小数；电量使用 `EnergyReading` 枚举区分未累计和值。

## 检查与资料

```sh
moon info
moon fmt --check
moon check --target native --deny-warn
moon test --target native --deny-warn
moon build --target native --release --deny-warn
python tools/test_integration.py
python -m pip install -r tools/requirements-reference.txt
python tools/test_reference.py
```

最后两条仅供开发验证，参考客户端不是产品运行依赖。测试范围与实机限制见[验证记录](docs/VALIDATION.zh-CN.md)。

- [项目申报书](docs/PROPOSAL.zh-CN.md) · [变更记录](CHANGELOG.md)
- [SunSpec 设备信息模型规范 1.2.1](https://sunspec.org/wp-content/uploads/2025/01/SunSpec-Device-Information-Model-Specificiation-V1-2-1.pdf)
- [SunSpec 官方模型与测试数据来源](tests/fixtures/sunspec/README.md)
- [Modbus 官方规范](https://www.modbus.org/modbus-specifications) · [pysunspec2 官方参考客户端](https://github.com/sunspec/pysunspec2)

项目代码采用 Apache-2.0；第三方模型文件保留各自来源和许可证。
