# MoonPV 预编译版

MoonPV 是 SunSpec Modbus TCP 只读客户端，支持三相逆变器 Model 103 和三相电表 Model 203 的选定字段。程序已编译，无需安装 MoonBit；本机模拟演示另需 Python 3.12+，无需额外 Python 包。

Windows 包用于 x86_64；Linux 包在 Ubuntu 24.04 x86_64 构建和测试，未验证其他发行版。请完整解压，以下命令均在解压后的目录运行。

## 先运行模拟演示

Windows PowerShell：

```powershell
.\bin\moonpv.exe --help
python tools/demo.py
```

Linux：

```sh
./bin/moonpv --help
python3 tools/demo.py
```

演示只连接本机随机端口，读取合成的逆变器和两块电表，核对读数后输出 `PASS`。逆变器为 `4200 W`，第一块电表为 `-1200 W`，第二块为 `3000 W`。这些是测试数据，**不是实机测量**。加 `--json` 可查看完整 JSON；模拟服务随程序退出关闭。

## 读取自己的设备

按厂商手册确认设备已启用 SunSpec Modbus TCP、端口、Unit ID 和零基 PDU 地址。以下地址仅为示例。

```powershell
.\bin\moonpv.exe sunspec 192.168.1.20 502 1 40000 --json
```

Linux 将 `.\bin\moonpv.exe` 换成 `./bin/moonpv`。直接读取设备不需要 Python。退出码 `0` 为成功，`1` 为读取失败，`2` 为参数错误；错误写入 stderr。

当前无写入、RTU、后台轮询或监控界面，也未完成真实设备验证。完整用法及限制见[项目仓库](https://github.com/STW135-2026/moonpv)。

`BUILD.json` 记录源代码提交、工具链及各文件 SHA-256；`LICENSE`、`NOTICE.txt` 和 `licenses/` 保留来源说明。下载页的 `.sha256` 文件可用于核对压缩包：Windows 用 `Get-FileHash 文件名 -Algorithm SHA256`，Linux 用 `sha256sum -c 文件名.sha256`。
