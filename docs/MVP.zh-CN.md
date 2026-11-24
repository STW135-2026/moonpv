# MoonPV MVP 验收

MoonPV 已完成从连接 SunSpec 设备、发现模型、读取数据到输出结果的只读流程。本页用本机模拟设备复现这条流程，不需要借用逆变器。模拟结果不能代替实机验证。

## 下载后运行

从 [v0.2.2 发布页](https://github.com/STW135-2026/moonpv/releases/tag/v0.2.2)下载对应系统的完整压缩包并解压。Windows 为 x86_64，Linux 版在 Ubuntu 24.04 x86_64 验证。模拟演示需要 Python 3.12+，不需要 MoonBit 或第三方 Python 包。

在解压目录运行：

```sh
python tools/demo.py
```

Linux 使用 `python3`。程序通过真实的本机 TCP 连接读取模拟数据，不是直接打印预设结果；读数与预期不符会返回失败。

```text
Model  Address  Active power  A-phase voltage
103    40070    4200 W        230.1 V
203    40122    -1200 W       230.0 V
203    40229    3000 W        230.0 V
Meter 40122: imported 250000 Wh; exported 120000 Wh
Meter 40229: imported 480000 Wh; exported not_accumulated
API example: Inverter active power: 4200 W
PASS: discovery, readings, accumulator status and API example
```

`python tools/demo.py --json` 输出完整 JSON。电表未累计的电量为 `null`，状态为 `not_accumulated`，不会当作有效零电量。

直接连接设备用 `bin/moonpv sunspec <host> <port> <unit> [base-address] --json`；Windows 程序为 `bin\moonpv.exe`。真实设备需启用 SunSpec Modbus TCP，并按手册配置参数。直接运行客户端不需要 Python。

## 还验证了什么

- [Windows/Linux CI](https://github.com/STW135-2026/moonpv/actions/workflows/ci.yml)：构建、21 项 MoonBit 测试、14 组 CLI/TCP 集成测试和 2 组官方 `pysunspec2` 参考客户端对照。
- [发布包检查](../tools/check_release.py)：解压到仓库外的含空格路径，清空 PATH、移除 MoonBit 环境后运行帮助、模拟演示和 JSON 输出，检查错误退出码与缺少文件的提示。
- 压缩包附 SHA-256；内部 `BUILD.json` 记录源码提交及文件校验值，发布页附两种系统的验收输出。

详细测试范围见[验证记录](VALIDATION.zh-CN.md)，真实开发过程见[提交记录](https://github.com/STW135-2026/moonpv/commits/main/)。

## 当前边界

支持 Model 103/203 的选定测量字段，无写入、RTU、后台采集或监控界面。尚无真实设备测试和 SunSpec 认证。项目价值是让 MoonBit 网关或采集程序复用现成的设备读取接口，后续存储与展示由使用方接入。
