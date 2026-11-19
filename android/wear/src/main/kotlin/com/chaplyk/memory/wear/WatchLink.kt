package com.chaplyk.memory.wear

import org.json.JSONObject

/// The protocol with the phone app (android/app WatchListenerService).
object WatchLink {
    const val PATH_PREFIX = "/watch-reminder/"
    const val ACK_PATH = "/watch-reminder/ack"

    /// What the phone said about one reminder.
    data class Ack(val id: String?, val ok: Boolean, val summary: String?, val emoji: String?, val time: String?, val error: String?) {
        /// "⏰ Call mom" style line.
        val title: String get() = listOfNotNull(emoji?.takeIf { it.isNotBlank() }, summary).joinToString(" ")

        val errorMessage: String
            get() = when (error) {
                "signed_out" -> "Open NagadAI on your phone and sign in"
                "empty" -> "Didn't catch that"
                else -> "Couldn't save it. Try again"
            }

        companion object {
            fun parse(bytes: ByteArray): Ack? = try {
                val json = JSONObject(String(bytes))
                Ack(
                    id = json.optString("id").ifEmpty { null },
                    ok = json.optBoolean("ok"),
                    summary = json.optString("summary").ifEmpty { null },
                    emoji = json.optString("emoji").ifEmpty { null },
                    time = json.optString("when").ifEmpty { null },
                    error = json.optString("error").ifEmpty { null },
                )
            } catch (e: Exception) {
                null
            }
        }
    }
}
