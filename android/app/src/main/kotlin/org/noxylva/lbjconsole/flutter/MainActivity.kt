package org.noxylva.lbjconsole.flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RtlTcpChannelHandler.registerWith(flutterEngine)
        AudioInputHandler.registerWith(flutterEngine, applicationContext)
    }
}