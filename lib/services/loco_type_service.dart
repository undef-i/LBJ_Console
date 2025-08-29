import 'package:lbjconsole/util/loco_type_util.dart';

class LocoTypeService {
  static final LocoTypeService _instance = LocoTypeService._internal();
  factory LocoTypeService() => _instance;
  LocoTypeService._internal();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    _isInitialized = true;
  }

  bool get isInitialized => _isInitialized;
}
