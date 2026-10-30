import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../util/app_log.dart';
import 'demod_worker.dart';
import 'rtl_tcp_service.dart';

class EmbeddedUsbService {
  EmbeddedUsbService._() {
    sessionActive.addListener(_syncConnecting);
    devicePresent.addListener(_syncLinkState);
    RtlTcpService().connectionStream.listen((_) => _syncLinkState());
  }
  static final EmbeddedUsbService instance = EmbeddedUsbService._();

  static const MethodChannel _methods =
      MethodChannel('org.noxylva.lbjconsole/usb_sdr');
  static const EventChannel _events =
      EventChannel('org.noxylva.lbjconsole/usb_sdr_event');

  final ValueNotifier<String> statusText = ValueNotifier<String>('');
  final ValueNotifier<bool> sessionActive = ValueNotifier<bool>(false);
  final ValueNotifier<bool> connecting = ValueNotifier<bool>(false);
  final ValueNotifier<bool> devicePresent = ValueNotifier<bool>(false);

  final ValueNotifier<int> linkState = ValueNotifier<int>(0);

  bool _attempting = false;

  void _syncConnecting() {
    connecting.value = sessionActive.value || _attempting;
    _syncLinkState();
  }

  void _syncLinkState() {
    final next = RtlTcpService().isConnected
        ? 2
        : (devicePresent.value || sessionActive.value || _attempting)
            ? 1
            : 0;
    if (linkState.value != next) linkState.value = next;
  }

  bool _active = false;
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<String>? _diagSubscription;

  bool _intentOn = false;
  Timer? _watchdog;
  int _noDataTicks = 0;
  int _lastStreamError = 0;
  int _watchBytesIn = 0;

  void _startWatchdog() {
    if (_watchdog != null) return;
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_intentOn) {
        _watchdog?.cancel();
        _watchdog = null;
        return;
      }
      try {
        final op = await _methods.invokeMethod<String>('opState') ?? '';
        final parts = op.split('|');
        if (parts.length == 3) {
          final secs = int.tryParse(parts[2]) ?? 0;
          if (secs >= 3) {
            const opNames = {
              'start-rtl': '启动 RTL',
              'start-pluto': '启动 Pluto',
              'stop': '停止',
            };
            _setStatus(
                '设备操作未完成：${opNames[parts[0]] ?? parts[0]}，阶段 ${parts[1]}，已 $secs 秒');
            return;
          }
        }
      } catch (_) {}
      if (!sessionActive.value) {
        if (_attempting) return;
        _attempting = true;
        _syncConnecting();
        try {
          _onStartResult(await _methods.invokeMethod<String>('start'));
        } catch (e) {
          _attempting = false;
          _syncConnecting();
          AppLog.error('usb-sdr', 'watchdog start failed', e);
        }
        return;
      }
      int err = 0;
      bool running = false;
      try {
        err = await _methods.invokeMethod<int>('exitError') ?? 0;
        running = await _methods.invokeMethod<bool>('isRunning') ?? false;
      } catch (_) {
        return;
      }
      if (!running) {
        sessionActive.value = false;
        _syncConnecting();
        if (err != 0) {
          _setStatus('会话已停止，错误码 $err');
        }
        return;
      }
      if (err != 0) {
        if (_lastStreamError != err) {
          _lastStreamError = err;
          _setStatus('数据读取失败，错误码 $err');
        }
        return;
      }
      _lastStreamError = 0;
      final rtl = RtlTcpService();
      final grew = rtl.lastBytesIn != _watchBytesIn;
      var diag = '';
      final lastAt = rtl.lastStatusAt;
      if (lastAt == null ||
          DateTime.now().difference(lastAt) > const Duration(seconds: 6)) {
        diag = '数据处理无响应';
        _noDataTicks = 0;
      } else if (!rtl.isConnected) {
        _noDataTicks++;
        if (_noDataTicks >= 3) diag = '数据连接未建立';
      } else if (!grew) {
        _noDataTicks++;
        if (_noDataTicks >= 3) diag = '未收到设备数据';
      } else {
        _noDataTicks = 0;
      }
      _watchBytesIn = rtl.lastBytesIn;
      const owned = {'', '数据处理无响应', '数据连接未建立', '未收到设备数据'};
      if (owned.contains(statusText.value) && statusText.value != diag) {
        _setStatus(diag);
      }
      if (rtl.isConnected && grew && statusText.value.isNotEmpty) {
        _setStatus('');
      }
    });
  }

  void _setStatus(String text) {
    statusText.value = text;
  }

  void _onStartResult(String? result) {
    switch (result) {
      case 'no_device':
        _setStatus('未检测到 USB 设备');
        break;
      case 'permission_requested':
        _setStatus('');
        break;
      case 'starting':
        _setStatus('');
        break;
    }
  }

  Future<bool> consumeAttachLaunch() async {
    try {
      return await _methods.invokeMethod<bool>('consumeAttachLaunch') ?? false;
    } catch (e) {
      AppLog.error('usb-sdr', 'consumeAttachLaunch failed', e);
      return false;
    }
  }

  Future<void> _ensureStarted() async {
    if (!_active) {
      _active = true;
      _subscription = _events.receiveBroadcastStream().listen(
      (dynamic event) {
        if (!_active || event is! Map) return;
        switch (event['state']) {
          case 'ready':
            _attempting = false;
            devicePresent.value = true;
            _syncConnecting();
            _setStatus('');
            sessionActive.value = true;
            RtlTcpService().connect(host: '127.0.0.1', port: '14423');
            break;
          case 'no_device':
            _attempting = false;
            final seen = (event['seen'] as String? ?? '').trim();
            devicePresent.value = seen.isNotEmpty;
            _syncConnecting();
            _setStatus(seen.isEmpty
                ? '未检测到 USB 设备'
                : '未发现匹配的设备，当前接入：$seen');
            break;
          case 'permission_requested':
            devicePresent.value = true;
            _setStatus('');
            break;
          case 'denied':
            _attempting = false;
            devicePresent.value = true;
            _syncConnecting();
            _setStatus('USB 访问权限被拒绝');
            break;
          case 'detached':
            devicePresent.value = false;
            sessionActive.value = false;
            _syncConnecting();
            _setStatus('');
            break;
          case 'error':
            _attempting = false;
            devicePresent.value = true;
            _syncConnecting();
            final message = (event['message'] as String? ?? '').trim();
            _setStatus(message.isEmpty
                ? '打开设备失败，错误码 ${event['code']}'
                : '打开设备失败，错误码 ${event['code']}，$message');
            break;
        }
      },
      onError: (Object e) {
        AppLog.error('usb-sdr', 'event stream failed', e);
      },
      );
      _diagSubscription = DemodWorker.instance.diagStream.listen((m) {
        _setStatus(m);
      });
    }
    try {
      final running =
          await _methods.invokeMethod<bool>('isRunning') ?? false;
      if (running) {
        devicePresent.value = true;
        sessionActive.value = true;
        RtlTcpService().connect(host: '127.0.0.1', port: '14423');
      } else {
        _onStartResult(await _methods.invokeMethod<String>('start'));
      }
    } catch (e) {
      AppLog.error('usb-sdr', 'start failed', e);
    }
  }

  Future<void> activate() async {
    _intentOn = true;
    _startWatchdog();
    if (_active) return;
    await _ensureStarted();
  }

  Future<void> connectNow() async {
    _intentOn = true;
    _startWatchdog();
    _attempting = true;
    _syncConnecting();
    await _ensureStarted();
  }

  Future<void> deactivate() async {
    _intentOn = false;
    _watchdog?.cancel();
    _watchdog = null;
    _setStatus('');
    _attempting = false;
    devicePresent.value = false;
    _syncConnecting();
    sessionActive.value = false;
    if (!_active) return;
    _active = false;
    await _subscription?.cancel();
    _subscription = null;
    await _diagSubscription?.cancel();
    _diagSubscription = null;
    await RtlTcpService().disconnect();
    try {
      await _methods.invokeMethod('stop');
    } catch (e) {
      AppLog.error('usb-sdr', 'stop failed', e);
    }
  }
}
