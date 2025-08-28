# LBJ Console

LBJ Console 是一款应用程序，用于通过 BLE 从 [SX1276_Receive_LBJ](https://github.com/undef-i/SX1276_Receive_LBJ) 设备接收并显示列车预警消息，功能包括：

- 接收列车预警消息，支持可选的手机推送通知。
- 在地图上显示预警消息的 GPS 信息。
- 基于内置数据文件显示机车配属，机车类型和车次类型。

主分支目前只适配了 Android 。如需在其它平台上面使用，请参考 [flutter](https://github.com/undef-i/LBJ_Console/tree/flutter) 分支自行编译。
## 数据文件

LBJ Console 依赖以下数据文件，位于 `app/src/main/assets/` 目录，用于支持机车配属和车次信息的展示：
- `loco_info.csv`：包含机车配属信息，格式为 `机车型号,机车编号起始值,机车编号结束值,所属铁路局及机务段,备注`。
- `loco_type_info.csv`：包含机车类型编码信息，格式为 `机车类型编码,机车类型`。
- `train_info.csv`：包含车次类型信息，格式为 `正则表达式,车次类型`。


# 许可证

该项目采用 GNU 通用公共许可证 v3.0（GPLv3）授权。该许可证确保软件保持免费和开源，要求任何修改或衍生作品也必须在相同许可证条款下发布。
