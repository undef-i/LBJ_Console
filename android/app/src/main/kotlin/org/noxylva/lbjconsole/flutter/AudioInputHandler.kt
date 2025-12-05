package org.noxylva.lbjconsole.flutter

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class AudioInputHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    private var audioRecord: AudioRecord? = null
    private val isRecording = AtomicBoolean(false)
    private var recordingThread: Thread? = null
    
    private val sampleRate = 48000
    private val bufferSize = AudioRecord.getMinBufferSize(
        sampleRate,
        AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT
    ) * 2

    companion object {
        private const val CHANNEL = "org.noxylva.lbjconsole/audio_input"
        private const val TAG = "AudioInputHandler"

        fun registerWith(flutterEngine: FlutterEngine, context: Context) {
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler(AudioInputHandler(context))
        }
    }

    private external fun nativePushAudio(data: ShortArray, size: Int)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                if (startRecording()) {
                    result.success(null)
                } else {
                    result.error("AUDIO_ERROR", "Failed to start audio recording", null)
                }
            }
            "stop" -> {
                stopRecording()
                result.success(null)
            }
            else -> result.notImplemented()
        }
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