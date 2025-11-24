package com.opendroids.tourbot.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

data class AppError(
    val timestamp: String,
    val message: String,
    val stackTrace: String? = null
)

@Singleton
class ErrorLogger @Inject constructor() {
    private val _errors = MutableStateFlow<List<AppError>>(emptyList())
    val errors: StateFlow<List<AppError>> = _errors.asStateFlow()

    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())

    fun logError(message: String, throwable: Throwable? = null) {
        val stackTrace = throwable?.stackTraceToString()
        val error = AppError(
            timestamp = dateFormat.format(Date()),
            message = message,
            stackTrace = stackTrace
        )
        _errors.update { currentErrors ->
            (currentErrors + error).takeLast(100) // Keep last 100 errors
        }
    }

    fun clearErrors() {
        _errors.value = emptyList()
    }
}
