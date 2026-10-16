package one.mixin.desktop.drop

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.common.StandardMethodCodec
import io.flutter.plugin.common.FlutterException
import java.nio.ByteBuffer

internal class FfiTransport(engine: Long, val handler: (MethodCall, Result) -> Unit) {
    interface Result {
        fun success(result: Any?)
        fun error(code: String, message: String?, details: Any?)
        fun notImplemented()
    }
    companion object { init { System.loadLibrary("desktop_drop_ffi") } }
    private val main = Handler(Looper.getMainLooper())
    private val codec = StandardMethodCodec.INSTANCE
    private val pending = mutableMapOf<Long, Result>()
    private var serial = 0L
    private var context = nativeCreate(engine)
    val decisionContext = nativeCreateDecision()
    val generation: Long get() = nativeDecisionGeneration(decisionContext)

    data class Decision(val generation: Long, val request: Long, val target: Long, val operation: Int)

    // This call returns through JNI directly, never through the main Handler.
    // The shared bridge chooses the isolate-owned callback or a bounded port wait.
    fun decide(session: Long, phase: Int, x: Double, y: Double, payload: Map<String, Any?>): Decision {
        val data = bytes(StandardMessageCodec.INSTANCE.encodeMessage(payload)!!)
        val result = nativeDecide(decisionContext, session, phase, x, y, data)
        return Decision(result[0], result[1], result[2], result[3].toInt())
    }
    private fun bytes(buffer: ByteBuffer): ByteArray {
        buffer.flip()
        return ByteArray(buffer.remaining()).also { buffer.get(it) }
    }
    // Called by JNI on the caller's thread. System operations stay on main.
    @Suppress("unused")
    private fun dispatch(context: Long, epoch: Long, request: Long, data: ByteArray) {
        main.post {
            if (this.context != context) return@post
            var replied = false
            val reply = { data: ByteArray ->
                if (!replied) { replied = true; nativeReply(context, epoch, request, data) }
            }
            val result = object : Result {
                override fun success(result: Any?) = reply(bytes(codec.encodeSuccessEnvelope(result)))
                override fun error(code: String, message: String?, details: Any?) =
                    reply(bytes(codec.encodeErrorEnvelope(code, message, details)))
                override fun notImplemented() = reply(ByteArray(0))
            }
            try { handler(codec.decodeMethodCall(ByteBuffer.wrap(data)), result) }
            catch (error: Exception) { result.error("native_error", error.message, null) }
        }
    }
    @Suppress("unused")
    private fun complete(token: Long, data: ByteArray) {
        main.post {
            val result = pending.remove(token) ?: return@post
            if (data.isEmpty()) result.notImplemented()
            else try { result.success(codec.decodeEnvelope(ByteBuffer.wrap(data))) }
            catch (error: FlutterException) { result.error(error.code, error.message, error.details) }
        }
    }
    fun invoke(method: String, args: Any?, result: Result? = null): Long {
        val token = if (result == null) 0 else ++serial
        if (result != null) pending[token] = result
        return nativeSend(context, bytes(codec.encodeMethodCall(MethodCall(method, args))), token)
    }
    fun close() {
        val old = context
        context = 0
        nativeDestroyDecision(decisionContext)
        nativeDestroy(old)
        val replies = pending.values.toList()
        pending.clear()
        replies.forEach { it.notImplemented() }
    }
    private external fun nativeCreate(engine: Long): Long
    private external fun nativeDestroy(context: Long)
    private external fun nativeSend(context: Long, bytes: ByteArray, token: Long): Long
    private external fun nativeCreateDecision(): Long
    private external fun nativeDestroyDecision(context: Long)
    private external fun nativeDecisionGeneration(context: Long): Long
    private external fun nativeDecide(context: Long, session: Long, phase: Int, x: Double, y: Double, bytes: ByteArray): LongArray
    private external fun nativeReply(context: Long, epoch: Long, request: Long, bytes: ByteArray)
}
