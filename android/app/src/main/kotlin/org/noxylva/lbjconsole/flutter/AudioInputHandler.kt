package org.noxylva.lbjconsole.flutter

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicBoolean
import java.nio.charset.Charset

class AudioInputHandler(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var audioRecord: AudioRecord? = null
    private val isRecording = AtomicBoolean(false)
    private var recordingThread: Thread? = null
    
    private val sampleRate = 48000
    private val bufferSize = AudioRecord.getMinBufferSize(
        sampleRate,
        AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT
    ) * 2

    private val handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var lastRecordingState: Boolean? = null
    private val messageRegex = "\\[MSG\\]\\s*(\\d+)\\|(-?\\d+)\\|(.*)".toRegex()

    companion object {
        private const val METHOD_CHANNEL = "org.noxylva.lbjconsole/audio_input"
        private const val EVENT_CHANNEL = "org.noxylva.lbjconsole/audio_input_event"
        private const val TAG = "AudioInputHandler"

        init {
            System.loadLibrary("railwaypagerdemod")
        }

        fun registerWith(flutterEngine: FlutterEngine, context: Context) {
            val handler = AudioInputHandler(context)
            val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            methodChannel.setMethodCallHandler(handler)
            val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            eventChannel.setStreamHandler(handler)
        }
    }

    private external fun nativePushAudio(data: ShortArray, size: Int)
    private external fun pollMessages(): ByteArray
    private external fun clearMessageBuffer()
    private external fun getAudioSpectrum(): FloatArray

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                clearMessageBuffer()
                if (startRecording()) {
                    result.success(null)
                } else {
                    result.error("AUDIO_ERROR", "Failed to start audio recording", null)
                }
            }
            "stop" -> {
                stopRecording()
                clearMessageBuffer()
                result.success(null)
            }
            "getSpectrum" -> {
                try {
                    val spectrum = getAudioSpectrum()
                    result.success(spectrum.toList())
                } catch (e: Exception) {
                    result.error("FFT_ERROR", "Failed to get spectrum", e.message)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.d(TAG, "EventChannel onListen")
        this.eventSink = events
        lastRecordingState = null
        startPolling()
    }

    override fun onCancel(arguments: Any?) {
        Log.d(TAG, "EventChannel onCancel")
        handler.removeCallbacksAndMessages(null)
        this.eventSink = null
    }

    private fun startPolling() {
        handler.post(object : Runnable {
            override fun run() {
                if (eventSink == null) {
                    return
                }

                val recording = isRecording.get()
                val logsBytes = pollMessages()
                val logs = if (logsBytes.isNotEmpty()) String(logsBytes, Charsets.ISO_8859_1) else ""

                if (lastRecordingState != recording) {
                    val statusMap = mutableMapOf<String, Any?>()
                    statusMap["listening"] = recording
                    eventSink?.success(statusMap)
                    lastRecordingState = recording
                }

                if (logs.isNotEmpty()) {
                    messageRegex.findAll(logs).forEach { match ->
                        try {
                            val dataMap = mutableMapOf<String, Any?>()
                            dataMap["address"] = match.groupValues[1]
                            dataMap["func"] = match.groupValues[2]
                            dataMap["numeric"] = match.groupValues[3]

                            eventSink?.success(dataMap)
                        } catch (e: Exception) {
                            Log.e(TAG, "decode_fail", e)
                        }
                    }
                }

                handler.postDelayed(this, 200)
            }
        })
    }

    private fun startRecording(): Boolean {
        if (isRecording.get()) return true

        if (ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "Permission not granted")
            return false
        }

        try {
            val audioSource = MediaRecorder.AudioSource.UNPROCESSED
            
            audioRecord = AudioRecord(
                audioSource,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord init failed")
                return false
            }

            audioRecord?.startRecording()
            isRecording.set(true)

            recordingThread = Thread {
                val buffer = ShortArray(bufferSize)
                while (isRecording.get()) {
                    val readSize = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                    if (readSize > 0) {
                        nativePushAudio(buffer, readSize)
                    }
                }
            }
            recordingThread?.priority = Thread.MAX_PRIORITY
            recordingThread?.start()
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Start recording exception", e)
            stopRecording()
            return false
        }
    }

    private fun stopRecording() {
        isRecording.set(false)
        try {
            recordingThread?.join(1000)
        } catch (e: InterruptedException) {
            e.printStackTrace()
        }
        
        try {
            if (audioRecord?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                audioRecord?.stop()
            }
            audioRecord?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Stop recording exception", e)
        }
        audioRecord = null
        recordingThread = null
    }
}
