# 相关项目与实现边界

复核日期：2026-11-17。检索 GitHub 仓库的 `sunspec language:MoonBit`、`sunspec moonbit`、`modbus language:MoonBit`、`SunSpec inverter`、`SunSpec Explorer`，并阅读下列项目说明。发布本仓库前，前两项查询均返回 0；这只是当时公开检索的结果，不代表不存在未收录或未公开的项目。

| 项目 | 重叠之处 | MoonPV 的边界 |
| --- | --- | --- |
| [qyt1234567/moonbit-modbus](https://github.com/qyt1234567/moonbit-modbus) | MoonBit Modbus 帧、寄存器和客户端相关逻辑 | 该项目说明其核心不绑定真实 TCP socket；MoonPV 提供异步 TCP 读取和 SunSpec 模型发现、103/203 字段解码。通用 Modbus 功能确有重叠，不作为创新点 |
| [668xin/modbus_lint](https://github.com/668xin/modbus_lint) | MoonBit 寄存器类型、值编码 | 对方主要校验用户提供的点表；MoonPV 连接设备读取其公布的 SunSpec 模型和实时数据 |
| [lycvvt/MoonPLC](https://github.com/lycvvt/Moonplc) | 工业通信、Modbus | 对方侧重软 PLC 与控制逻辑；MoonPV 是光伏设备的只读客户端 |
| [sunspec/pysunspec2](https://github.com/sunspec/pysunspec2) | SunSpec 设备发现、模型与数值读取，功能方向直接相近 | 官方 Python 实现覆盖更广；MoonPV 是较小范围的 MoonBit 原生实现，并用该客户端做独立对照 |
| [otfabric/sunspec-explorer](https://github.com/otfabric/sunspec-explorer) | 只读模型扫描和遥测 | 对方是带桌面/浏览器界面、轮询和导出的完整工具；MoonPV 提供 MoonBit API 与单次读取 CLI |
| [volkszaehler/mbmd](https://github.com/volkszaehler/mbmd) | 逆变器与电表采集 | 对方是提供 HTTP/MQTT 的 Go 采集服务；MoonPV 不实现这些服务，供 MoonBit 程序直接集成 |

## 为什么继续做这个范围

设备接入是已有标准和成熟实现支撑的需求。MoonPV 的交付目标是：MoonBit 程序拿到模型地址、带状态的原始数据和精确缩放结果，脚本能可靠区分成功和失败。多电表选择、异常连接关闭、可重复的离线演示和参考客户端对照，都服务于这条接入路径。它们是必要的工程能力，不是全新的协议或算法。

MoonPV 当前没有依赖上述通用 Modbus 库，也不是对其接口的直接扩展包。已实现的只读 TCP 层为 SunSpec 读取服务；后续如改用通用传输库，应保留 SunSpec 上层接口并说明依赖关系，不能据此宣称已经完成生态集成。

## 来源和贡献

- SunSpec 字段位置、类型及特殊值来自官方规范；标准本身不是原创成果。
- `tests/fixtures/sunspec/` 中三份 JSON 模型定义与许可证原样保留，来源固定到官方提交；未将其计为自行实现的代码。
- 项目自有实现为 MoonBit TCP 客户端、SunSpec 读取、CLI、示例和测试。Python 仅用于本机模拟、对照测试和工具链安装，不承担产品运行逻辑。
- 参考客户端 `pysunspec2==1.3.7` 仅为可选验证依赖，未复制其实现。

这里说明的是功能与集成方式上的差别，不是代码相似度检测报告，也不能代替组委会对选题价值和重复性的判断。
