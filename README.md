# LBJ_Console

LBJ Console 是一款应用程序，用于通过 BLE 从 [SX1276_Receive_LBJ](https://github.com/undef-i/SX1276_Receive_LBJ) 设备接收并显示列车预警消息，功能包括：

- 接收列车预警消息，支持可选的手机推送通知。
- 监控指定列车的轨迹，在地图上显示。
- 在地图上显示预警消息的 GPS 信息。
- 基于内置数据文件显示机车配属，机车类型和车次类型。

[android](https://github.com/undef-i/LBJ_Console/tree/android) 分支包含项目早期基于 Android 平台的实现代码，已实现基本功能，现已停止开发。

## 数据文件

LBJ Console 依赖以下数据文件，位于 `assets` 目录，用于支持机车配属和车次信息的展示：

- `loco_info.csv`：包含机车配属信息，格式为 `机车型号,机车编号起始值,机车编号结束值,所属铁路局及机务段,备注`。
- `loco_type_info.csv`：包含机车类型编码信息，格式为 `机车类型编码前缀,机车类型`。
- `train_info.csv`：包含车次类型信息，格式为 `正则表达式,车次类型`。

数据来源于网络，可能存在错误或不完整，欢迎通过提交 Pull Request 共同完善数据准确性。

# 许可证

该项目采用 GNU 通用公共许可证 v3.0（GPLv3）授权。
