# MoonPV 项目申报书

**项目名称：** MoonPV：MoonBit 光伏设备 SunSpec 读取工具  
**项目类型：** MoonBit 协议库与命令行工具

## 项目目标与应用场景

光伏逆变器和电表会通过 Modbus TCP 提供运行数据，但接入程序仍要知道设备支持哪些 SunSpec 模型、模型位于哪些寄存器，以及如何应用缩放因子。MoonPV 按公开的 SunSpec 模型链发现设备数据，并读取逆变器 Model 103 和电表 Model 203 的常用测量值；电表的输入/输出累计电量可供本地能量监测程序区分取电和送电。

目标用户是编写 MoonBit 边缘网关、采集服务或设备联调工具的开发者。首版只读，不控制设备。

## 交付物与使用方式

- MoonBit API：连接 Modbus TCP 设备、发现 SunSpec 模型链、读取 Model 103 和 Model 203 的常用点。
- Native CLI：输入主机、端口、Unit ID 和可选基地址，输出模型 ID、寄存器地址、逆变器测量值与电表输入/输出电量。
- README、示例代码、协议测试和申报材料。

使用流程：确认设备已启用 Modbus TCP 和 SunSpec → 按设备手册选择 Unit ID/基地址 → 运行 CLI 或在 MoonBit 服务中调用库 → 按原始值和缩放因子处理测量数据。

## 技术路线

项目主要使用 MoonBit，底层网络连接使用官方 `moonbitlang/async` socket。模块分为 Modbus TCP 帧收发与校验、SunSpec 标记和模型链发现、Model 103/203 字段解码、CLI 输出四部分。读取字段位置依据 SunSpec Alliance 的规范和官方模型定义；原始整数与缩放因子分开返回，避免在库内引入浮点舍入。

开发过程中使用 AI 工具辅助检索资料、整理字段布局、起草代码与测试；实现以官方规范和模型定义复核，并通过 MoonBit 检查、测试、构建及本机 TCP 模拟设备验证。代码和结果由参赛者审核后提交。

## 测试与验收

验收关键路径：`moon check --target native`、`moon test --target native`、`moon build --target native --release`；测试覆盖 Modbus 帧校验、SunSpec 标记、模型链长度和地址计算、Model 103/203 缩放因子与未实现值处理。可复现的本机 TCP 模拟测试不依赖真实设备；接入实机时再按厂商手册核对 Unit ID、基地址和启用状态。

## 风险与应对

- 设备可能使用不同 SunSpec 基地址或 Unit ID：允许指定基地址，并提供常见地址探测；README 提醒以设备手册为准。
- 不同厂商可能只实现部分模型或数据点：首版只声明 Model 103/203 的选定点，对标准未实现值作显式处理，不把缺失值当作零。
- 厂商扩展字段不属于统一模型：首版不猜测、不写入控制点，后续扩展需基于公开模型或具体设备手册。

## 相关项目与差异

MoonBit 生态中已有 MoonPLC，侧重软 PLC 运行时和 IEC 61131-3 编程；本项目做 SunSpec 客户端侧的数据发现和只读遥测。其他生态已有 SunSpec Dashboard 和模型工具，证明标准有实际使用场景；MoonPV 的交付重点是 MoonBit 可复用 API 和 CLI，不声称发明协议或覆盖全部 SunSpec 模型。具体检索记录见[差异化说明](DIFFERENTIATION.zh-CN.md)。
