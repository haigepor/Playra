package com.example.kazumi

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** 固定模块、后台执行；此通道不接收脚本名、命令或私有目录。 */
class SourceRuntimeBridge(messenger: BinaryMessenger, context: Context) : MethodChannel.MethodCallHandler {
    private val application = context.applicationContext
    private val channel = MethodChannel(messenger, "com.predidit.kazumi/source-runtime")
    private val main = Handler(Looper.getMainLooper())
    private val pending = ConcurrentHashMap<String, AtomicBoolean>()
    private val alive = AtomicBoolean(true)

    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val id = args?.get("requestId") as? String
        if (args == null || id == null || !id.matches(Regex("[A-Za-z0-9_-]{1,64}"))) {
            result.success(error("INVALID_ARGUMENT")); return
        }
        if (call.method == "cancel") {
            cancel(id); result.success(null); return
        }
        if (call.method != "request") { result.notImplemented(); return }
        val raw = args["payloadJson"] as? String
        val budget = args["timeoutMs"] as? Int
        if (raw == null || raw.toByteArray(Charsets.UTF_8).size > 32768 || budget == null || budget !in 1..60000) {
            result.success(error("INVALID_ARGUMENT")); return
        }
        val cancelled = AtomicBoolean(false)
        if (pending.putIfAbsent(id, cancelled) != null) {
            result.success(error("INVALID_ARGUMENT")); return
        }
        val started = SystemClock.elapsedRealtime()
        try {
            workers.execute {
                val response = try {
                    if (cancelled.get()) error("CANCELLED") else {
                        val module = module(application)
                        val remaining = budget - (SystemClock.elapsedRealtime() - started).toInt()
                        when {
                            cancelled.get() -> error("CANCELLED")
                            remaining <= 0 -> error("TIMEOUT")
                            else -> module.callAttr("request", raw, id, remaining).toString().let {
                                if (it.toByteArray(Charsets.UTF_8).size <= 2 * 1024 * 1024) it else error("RESPONSE_TOO_LARGE")
                            }
                        }
                    }
                } catch (_: LinkageError) { error("RUNTIME_UNAVAILABLE") }
                catch (_: Exception) { error("RUNTIME_ERROR") }
                finally { pending.remove(id) }
                main.post { if (alive.get()) result.success(response) }
            }
        } catch (_: RejectedExecutionException) {
            pending.remove(id); result.success(error("BUSY"))
        }
    }

    private fun cancel(id: String) {
        val flag = pending[id] ?: return
        if (!flag.compareAndSet(false, true)) return
        // 取消不能排在业务工作池后面，否则四个慢请求会阻塞取消。
        cancellations.execute {
            try { pythonModule?.callAttr("cancel", id) } catch (_: Exception) { }
        }
    }

    fun dispose() {
        alive.set(false)
        channel.setMethodCallHandler(null)
        pending.keys.toList().forEach { cancel(it) }
    }

    companion object {
        private val workers = ThreadPoolExecutor(4, 4, 0L, TimeUnit.MILLISECONDS, LinkedBlockingQueue<Runnable>(8))
        private val cancellations = Executors.newSingleThreadExecutor()
        @Volatile private var pythonModule: PyObject? = null
        private val startup = Any()
        private fun module(context: Context): PyObject = synchronized(startup) {
            pythonModule ?: run {
                if (!Python.isStarted()) Python.start(AndroidPlatform(context))
                Python.getInstance().getModule("android_bridge").also {
                    // 私有身份路径只由原生 applicationContext 提供，不接受 Flutter 参数覆盖。
                    it.callAttr("configure", context.filesDir.absolutePath)
                    pythonModule = it
                }
            }
        }
        private fun error(code: String) = "{\"error\":{\"code\":\"$code\",\"message\":\"$code\"}}"
    }
}
