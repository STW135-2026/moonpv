# 选题检索与差异化

**检索日期：2026-11-15**

## 检索结论

检索了 GitHub、Mooncakes 和 MoonBit 社区项目中的 `MoonBit Modbus`、`MoonBit SunSpec`、`MoonBit solar`、`SunSpec inverter` 等关键词。公开检索结果里发现 MoonBit 的 MoonPLC，也发现多个其他语言的 SunSpec 客户端和设备工具；没有据此得出“绝对不存在相同项目”的结论。

## 相近项目

- [lycvvt/MoonPLC](https://github.com/lycvvt/Moonplc)：MoonBit 软 PLC 运行时和 IEC 61131-3 编程工具，也包含通用 Modbus 通信。它的核心交付是 PLC 逻辑运行和仿真；MoonPV 的核心交付是 SunSpec 模型链发现、Model 103 逆变器数据解码和 MoonBit 客户端 API。两者处于相邻的工业通信领域，因此本项目不再做通用 PLC 或通用 Modbus 工具。
- [SunSpec 官方模型定义](https://github.com/sunspec/models)：SunSpec Alliance 发布的标准模型数据，是本项目实现时使用的规范来源，不是本项目自行编写的模型定义。
- [SunSpec Dashboard](https://sunspec.org/sunspec-dashboard/)：官方设备交互和模型浏览工具，能实时连接设备。本项目不替代它，定位是供 MoonBit 程序依赖的 API 与轻量 CLI。
- [OT Fabric SunSpec Explorer](https://otfabric.io/projects/sunspec-explorer/)：其他生态的 SunSpec 桌面浏览器，可扫描和展示模型数据。功能方向相近，说明这类设备接入有现实需求，也说明本项目不能把“设备扫描”说成新发明。

## 本项目的具体边界

MoonPV 不是通用软 PLC、Modbus 服务端或桌面寄存器浏览器。它将 SunSpec 设备模型发现、模型链地址定位和 Model 103 逆变器、Model 203 电表的选定点解码做成 MoonBit 库，供 MoonBit 网关、采集程序和监测服务集成。首版只读、只支持 Modbus TCP，不做控制指令，也不声称完整兼容所有 SunSpec 模型。

检索覆盖公开 GitHub 和 Mooncakes 页面，不能代替赛事组委会的重复性审查；提交前仍应核对当期参赛规则，并在 README 与申报材料中如实说明实现范围和参考来源。
