package juicewrldapi.music_library_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.MediaMetadataRetriever

class MainActivity : FlutterActivity() {
    private val channelName = "native_metadata"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method != "read") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val args = call.arguments as? Map<*, *>
            val filePath = args?.get("filePath") as? String
            if (filePath.isNullOrBlank()) {
                result.success(mapOf<String, Any?>())
                return@setMethodCallHandler
            }

            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(filePath)

                val title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
                val artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                val album = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
                val genre = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_GENRE)
                val yearStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR)
                val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                val artwork = retriever.embeddedPicture

                val year = yearStr?.toIntOrNull()
                val durationMs = durationStr?.toLongOrNull()?.toInt()

                val payload: MutableMap<String, Any?> = HashMap()
                payload["title"] = title
                payload["artist"] = artist
                payload["album"] = album
                payload["genre"] = genre
                payload["year"] = year
                payload["durationMs"] = durationMs
                payload["artworkBytes"] = artwork

                result.success(payload)
            } catch (e: Exception) {
                result.success(mapOf<String, Any?>())
            } finally {
                try {
                    retriever.release()
                } catch (_: Exception) {
                }
            }
        }
    }
}
