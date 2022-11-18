package one.mixin.oggOpusPlayer

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.os.Message
import java.util.concurrent.CountDownLatch

class DispatchQueue(threadName: String) : Thread() {
    @Volatile
    private var handler: Handler? = null
    private val syncLatch = CountDownLatch(1)

    init {
        name = threadName
        start()
    }

    @Suppress("unused")
    fun sendMessage(msg: Message, delay: Int = 0) {
        try {
            syncLatch.await()
            if (delay <= 0) {
                handler!!.sendMessage(msg)
            } else {
                handler!!.sendMessageDelayed(msg, delay.toLong())
            }
        } catch (_: Exception) {
        }
    }

    fun cancelRunnable(runnable: Runnable) {
        try {
            syncLatch.await()
            handler!!.removeCallbacks(runnable)
        } catch (_: Exception) {
        }
    }

    @JvmOverloads
    fun postRunnable(runnable: Runnable, delay: Long = 0) {
        try {
            syncLatch.await()
            if (delay <= 0) {
                handler!!.post(runnable)
            } else {
                handler!!.postDelayed(runnable, delay)
            }
        } catch (_: Exception) {
        }
    }

    @Suppress("unused")
    fun cleanupQueue() {
        try {
            syncLatch.await()
            handler!!.removeCallbacksAndMessages(null)
        } catch (_: Exception) {
        }
    }

    fun handleMessage(@Suppress("UNUSED_PARAMETER") inputMessage: Message) {
    }

    override fun run() {
        Looper.prepare()
        handler = @SuppressLint("HandlerLeak")
        object : Handler() {
            override fun handleMessage(msg: Message) {
                this@DispatchQueue.handleMessage(msg)
            }
        }
        syncLatch.countDown()
        Looper.loop()
    }
}
