package it.pietrodefilippis.tkftp

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * L'app è in Flutter; qui restano il salvataggio dei file scaricati nella cartella Download del telefono
 * (da Android 10 passa da MediaStore, prima si scrive direttamente) e il file condiviso col computer
 * (tk-ftp-siti.xml, per esempio nella cartella Dropbox): scelto una volta, resta collegato col permesso
 * persistente di Android e si rilegge/riscrive senza chiederlo di nuovo.
 */
class MainActivity : FlutterActivity() {

    private var inAttesa: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TkAggiornamento.registra(flutterEngine, this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tkftp/nativo").setMethodCallHandler { call, result ->
            when (call.method) {
                "salvaInDownload" -> Thread {
                    val esito = runCatching {
                        salvaInDownload(File(call.argument<String>("percorso")!!), call.argument<String>("nome")!!)
                    }
                    runOnUiThread {
                        esito.fold({ result.success(it) }, { result.error("salva", it.message, null) })
                    }
                }.start()
                "scegliFile" -> {
                    if (inAttesa != null) { result.error("occupato", "Scelta file già aperta", null); return@setMethodCallHandler }
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }
                    inAttesa = result
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, RICHIESTA_FILE)
                }
                "infoFile" -> inSecondoPiano(result) { info(Uri.parse(call.argument<String>("uri")!!)) }
                "leggiFile" -> inSecondoPiano(result) {
                    contentResolver.openInputStream(Uri.parse(call.argument<String>("uri")!!))?.use { it.readBytes() }
                        ?: throw IllegalStateException("Impossibile leggere il file")
                }
                "scriviFile" -> inSecondoPiano(result) {
                    val uri = Uri.parse(call.argument<String>("uri")!!)
                    contentResolver.openOutputStream(uri, "wt")?.use { it.write(call.argument<ByteArray>("dati")!!) }
                        ?: throw IllegalStateException("Impossibile scrivere il file")
                    info(uri)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Lavoro su file (anche di rete, Dropbox) fuori dal thread dell'interfaccia. */
    private fun inSecondoPiano(result: MethodChannel.Result, lavoro: () -> Any?) {
        Thread {
            try {
                val r = lavoro()
                runOnUiThread { result.success(r) }
            } catch (e: Exception) {
                runOnUiThread { result.error("file", e.message ?: e.toString(), null) }
            }
        }.start()
    }

    private fun info(uri: Uri): Map<String, Any?> {
        var nome = ""
        var modificato = 0L
        var dimensione = 0L
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let { nome = c.getString(it) ?: "" }
                c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 && !c.isNull(it) }?.let { dimensione = c.getLong(it) }
                c.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                    .takeIf { it >= 0 && !c.isNull(it) }?.let { modificato = c.getLong(it) }
            }
        } ?: throw IllegalStateException("File non raggiungibile")
        return mapOf("uri" to uri.toString(), "nome" to nome, "modificato" to modificato, "dimensione" to dimensione)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != RICHIESTA_FILE) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = inAttesa ?: return
        inAttesa = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        // permesso persistente: il file resta collegato anche dopo il riavvio del telefono
        try {
            contentResolver.takePersistableUriPermission(uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        } catch (_: Exception) {
            try { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) { }
        }
        inSecondoPiano(result) { info(uri) }
    }

    private fun salvaInDownload(origine: File, nome: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val valori = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, nome)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, valori)
                ?: throw IllegalStateException("cartella Download non disponibile")
            contentResolver.openOutputStream(uri)!!.use { out -> origine.inputStream().use { it.copyTo(out) } }
            valori.clear()
            valori.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, valori, null, null)
            origine.delete()
            return nome
        }
        @Suppress("DEPRECATION")
        val cartella = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        cartella.mkdirs()
        val dest = File(cartella, nome)
        origine.copyTo(dest, overwrite = true)
        origine.delete()
        return dest.absolutePath
    }

    companion object {
        private const val RICHIESTA_FILE = 4201
    }
}
