# LBJ Console

LBJ Console 是一款 Android 应用程序，用于通过 BLE 从 [SX1276_Receive_LBJ](https://github.com/undef-i/SX1276_Receive_LBJ) device 设备接收并显示列车预警消息，功能包括：

- 接收列车预警消息，支持可选的手机推送通知。
- 显示预警消息的 GPS 信息于地图。
- 基于内置数据文件显示机车配属和车次类型。


## 数据文件

LBJ Console 依赖以下数据文件，位于 `app/src/main/assets/` 目录，用于支持机车配属和车次信息的展示：
- `loco_info.csv`：包含机车配属信息，格式为 `机车型号,机车编号起始值,机车编号结束值,所属铁路局及机务段,备注`。
- `train_info.csv`：包含车次类型信息，格式为 `正则表达式,车次类型`。


# 许可证

该项目采用 GNU 通用公共许可证 v3.0（GPLv3）授权。该许可证确保软件保持免费和开源，要求任何修改或衍生作品也必须在相同许可证条款下发布。