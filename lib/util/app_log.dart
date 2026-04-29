import 'dart:developer' as developer;

class AppLog {
  const AppLog._();

  static void info(String scope, String message) {
    developer.log('$scope: $message', name: 'LBJ');
  }

  static void warn(String scope, String message) {
    developer.log('$scope: $message', name: 'LBJ', level: 900);
  }

  static void error(String scope, String message, [Object? error]) {
    final details = error == null ? message : '$message: $error';
    developer.log('$scope: $details', name: 'LBJ', level: 1000);
  }
}
