package org.noxylva.lbjconsole.flutter

object LbjUsbNative {
    init {
        System.loadLibrary("lbjusb")
    }

    external fun nativeStart(fd: Int): Int
    external fun nativeStartPluto(fd: Int, ifnum: Int): Int
    external fun nativeStop()
    external fun nativeIsRunning(): Boolean
    external fun nativeExitError(): Int
    external fun nativeStage(): String
    external fun nativeReset(fd: Int): Int
}
