import okhttp3.OkHttpClient
import java.security.cert.X509Certificate
import javax.net.ssl.*

fun getUnsafeOkHttpClient(): OkHttpClient {
    try {
        // ایجاد یک TrustManager که به تمام گواهینامه‌ها اعتماد می‌کند
        val trustAllCerts = arrayOf<TrustManager>(
            object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
                override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
                override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
            }
        )

        // ایجاد SSLContext با استفاده از TrustManager سفارشی
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, trustAllCerts, java.security.SecureRandom())

        // ایجاد OkHttpClient با SSLContext سفارشی
        return OkHttpClient.Builder()
            .sslSocketFactory(sslContext.socketFactory, trustAllCerts[0] as X509TrustManager)
            .hostnameVerifier { _, _ -> true } // غیرفعال کردن بررسی hostname
            .build()
    } catch (e: Exception) {
        throw RuntimeException(e)
    }
}

