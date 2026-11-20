# MoonPV 项目申报书

**项目名称：** MoonPV：MoonBit 光伏设备 SunSpec 读取工具

**参赛者：** 苏天纬

**GitHub：** https://github.com/STW135-2026/moonpv

## 用途与意义

MoonPV 面向通过 SunSpec Modbus TCP 提供数据的光伏逆变器和电表，为 MoonBit 网关、采集程序提供设备读取接口。

例如，本地监测程序需要显示逆变器当前发电功率、电表功率和累计电量。MoonPV 负责连接设备、查找数据地址、解码读数和处理读取错误，开发者可将结果接入自己的存储或展示程序，减少重复编写底层接入代码的工作。

## 已完成的功能

- 发现 SunSpec 模型，读取三相逆变器 Model 103、三相电表 Model 203 的三相电压、有功功率和频率，以及电表累计输入/输出电量。
- 按地址选择同一设备模型表中的不同电表实例，识别缺失值和未累计电量，处理请求超时。
- 提供 MoonBit API 和命令行工具，输出文本或带单位、状态、精确小数的 JSON；附有可执行示例和本机模拟演示。

## 复用价值与已有项目的关系

项目按标准模型定位字段。接入另一台采用已支持模型的设备时，可复用读取接口，连接参数仍需按设备手册配置。MoonBit 程序可直接调用库，其他脚本可读取 CLI 的 JSON，无需各自重写寄存器解码和数值换算。

已有官方 Python 客户端和通用 Modbus 工具。MoonPV 主要用 MoonBit 实现，网络层使用官方 `moonbitlang/async`，交付重点是 MoonBit 可直接调用的 SunSpec 读取能力。标准及模型定义来自 SunSpec Alliance，来源和功能重叠见[对比说明](DIFFERENTIATION.zh-CN.md)。

## 验证与边界

Windows、Linux 已通过构建、MoonBit 测试、本机 TCP 模拟测试及官方 `pysunspec2` 客户端结果对照。提供预编译程序和模拟演示包，可按 [MVP 验收步骤](MVP.zh-CN.md)直接试用；详细范围见[验证记录](VALIDATION.zh-CN.md)。

当前只读，仅支持上述模型的选定字段，不包含设备控制、存储和监控界面，尚未完成实机验证。开发中使用 AI 辅助检索、编码和测试。
