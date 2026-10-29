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
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class AudioInputHandler(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var audioRecord: AudioRecord? = null
    private val isRecording = AtomicBoolean(false)
    private var recordingThread: Thread? = null
    private var forwardThread: Thread? = null
    private val chunkQueue = ArrayBlockingQueue<ShortArray>(16)
    private val droppedChunks = AtomicLong(0)

    private val sampleRate = 48000
    private val bufferSize = AudioRecord.getMinBufferSize(
        sampleRate,
        AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT
    ) * 2

    private val handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    companion object {
        private const val METHOD_CHANNEL = "org.noxylva.lbjconsole/audio_input"
        private const val EVENT_CHANNEL = "org.noxylva.lbjconsole/audio_input_event"
        private const val TAG = "AudioInputHandler"

        fun registerWith(flutterEngine: FlutterEngine, context: Context) {
            val handler = AudioInputHandler(context)
            val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            methodChannel.setMethodCallHandler(handler)
            val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            eventChannel.setStreamHandler(handler)
        }
    }

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

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
        val statusMap = mutableMapOf<String, Any?>()
        statusMap["listening"] = isRecording.get()
        events?.success(statusMap)
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    private fun sendListeningState() {
        val recording = isRecording.get()
        handler.post {
            val sink = eventSink ?: return@post
            val statusMap = mutableMapOf<String, Any?>()
            statusMap["listening"] = recording
            sink.success(statusMap)
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
            chunkQueue.clear()
            droppedChunks.set(0)
            sendListeningState()

            recordingThread = Thread {
                val buffer = ShortArray(bufferSize)
                while (isRecording.get()) {
                    val readSize = audioRecord?.read(buffer, 0, buffer.size) ?: -1
                    when {
                        readSize > 0 -> {
                            val chunk = buffer.copyOf(readSize)
                            if (!chunkQueue.offer(chunk)) {
                                val dropped = droppedChunks.incrementAndGet()
                                if (dropped % 50L == 1L) {
                                    Log.w(TAG, "audio queue full, dropped chunks: $dropped")
                                }
                            }
                        }
                        readSize < 0 -> {
                            Log.e(TAG, "AudioRecord read error: $readSize")
                            isRecording.set(false)
                            handler.post { stopRecording() }
                        }
                    }
                }
            }
            recordingThread?.priority = Thread.MAX_PRIORITY
            recordingThread?.start()

            forwardThread = Thread {
                while (isRecording.get() || chunkQueue.isNotEmpty()) {
                    val chunk = try {
                        chunkQueue.poll(100, TimeUnit.MILLISECONDS)
                    } catch (e: InterruptedException) {
                        null
                    } ?: continue
                    val bytes = ByteArray(chunk.size * 2)
                    ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().put(chunk)
                    handler.post {
                        eventSink?.success(bytes)
                    }
                }
            }
            forwardThread?.start()
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
            if (audioRecord?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                audioRecord?.stop()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Stop recording exception", e)
        }
        try {
            recordingThread?.join(1000)
            forwardThread?.join(1000)
        } catch (e: InterruptedException) {
            e.printStackTrace()
        }

        try {
            audioRecord?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Release recording exception", e)
        }
        audioRecord = null
        recordingThread = null
        forwardThread = null
        chunkQueue.clear()
        sendListeningState()
    }
}
