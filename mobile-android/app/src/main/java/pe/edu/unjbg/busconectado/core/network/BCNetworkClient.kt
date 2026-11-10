package pe.edu.unjbg.busconectado.core.network

import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.logging.HttpLoggingInterceptor
import pe.edu.unjbg.busconectado.core.security.EncryptedStorage
import java.util.concurrent.TimeUnit

class AuthInterceptor(private val storage: EncryptedStorage) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        val builder = original.newBuilder()

        storage.getAccessToken()?.let { token ->
            builder.header("Authorization", "Bearer $token")
        }

        val response = chain.proceed(builder.build())

        if (response.code == 401) {
            // Sesión única revocada por inicio en otro dispositivo (Estilo Yape)
            storage.clearSession()
        }

        return response
    }
}

object BCNetworkClient {
    private const val BASE_URL = "https://api.bc-tacna.pe/api/v1/"

    fun createHttpClient(storage: EncryptedStorage): OkHttpClient {
        return OkHttpClient.Builder()
            .addInterceptor(AuthInterceptor(storage))
            .addInterceptor(HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BODY
            })
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .build()
    }
}
