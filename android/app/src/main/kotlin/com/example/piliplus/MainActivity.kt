package com.example.piliplus

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val PROFILE_BACKUP_CHANNEL =
            "com.snyb12138.piliplus.purify/profile_backup"
        private const val PICK_BACKUP_DIRECTORY = 34071
    }

    private var directoryPickerResult: MethodChannel.Result? = null
    private val backupExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PROFILE_BACKUP_CHANNEL,
        ).setMethodCallHandler(::handleProfileBackupCall)
    }

    private fun handleProfileBackupCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> pickBackupDirectory(
                call.argument<String>("initialUri"),
                result,
            )

            "hasBackup" -> runBackupOperation(result) {
                val treeUri = call.requireTreeUri()
                val targetName = call.requireString("targetName")
                val previousName = call.requireString("previousName")
                findChild(treeUri, targetName) != null ||
                    findChild(treeUri, previousName) != null
            }

            "readFile" -> runBackupOperation(result) {
                val treeUri = call.requireTreeUri()
                val name = call.requireString("name")
                findChild(treeUri, name)?.let { uri ->
                    contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: throw FileNotFoundException(name)
                }
            }

            "writeBackup" -> runBackupOperation(result) {
                val treeUri = call.requireTreeUri()
                val targetName = call.requireString("targetName")
                val previousName = call.requireString("previousName")
                val bytes = call.argument<ByteArray>("bytes")
                    ?: throw IllegalArgumentException("Missing bytes")
                writeBackup(treeUri, targetName, previousName, bytes)
                true
            }

            else -> result.notImplemented()
        }
    }

    private fun pickBackupDirectory(initialUri: String?, result: MethodChannel.Result) {
        if (directoryPickerResult != null) {
            result.error("PICKER_BUSY", "Directory picker is already open", null)
            return
        }
        directoryPickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
            if (!initialUri.isNullOrBlank()) {
                runCatching { Uri.parse(initialUri) }
                    .getOrNull()
                    ?.let { putExtra(DocumentsContract.EXTRA_INITIAL_URI, it) }
            }
        }
        try {
            startActivityForResult(intent, PICK_BACKUP_DIRECTORY)
        } catch (error: Exception) {
            directoryPickerResult = null
            result.error("PICKER_FAILED", error.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_BACKUP_DIRECTORY) return
        val result = directoryPickerResult ?: return
        directoryPickerResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            result.error("NO_DIRECTORY", "No directory was returned", null)
            return
        }
        try {
            val takeFlags = (data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
            if (takeFlags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION == 0) {
                throw SecurityException("The selected directory is read-only")
            }
            contentResolver.takePersistableUriPermission(uri, takeFlags)
            result.success(
                mapOf(
                    "uri" to uri.toString(),
                    "label" to queryDisplayName(treeDocumentUri(uri)),
                ),
            )
        } catch (error: Exception) {
            result.error("DIRECTORY_PERMISSION", error.message, null)
        }
    }

    private fun runBackupOperation(
        result: MethodChannel.Result,
        operation: () -> Any?,
    ) {
        backupExecutor.execute {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "PROFILE_BACKUP_IO",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }
    }

    private fun MethodCall.requireTreeUri(): Uri {
        val raw = requireString("directoryUri")
        val uri = Uri.parse(raw)
        if (uri.scheme != "content") {
            throw IllegalArgumentException("Backup directory needs authorization")
        }
        return uri
    }

    private fun MethodCall.requireString(name: String): String =
        argument<String>(name)?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("Missing $name")

    private fun treeDocumentUri(treeUri: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )

    private fun queryDisplayName(documentUri: Uri): String {
        contentResolver.query(
            documentUri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return DocumentsContract.getTreeDocumentId(documentUri)
    }

    private fun findChild(treeUri: Uri, name: String): Uri? {
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            documentId,
        )
        contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == name) {
                    return DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        cursor.getString(0),
                    )
                }
            }
        }
        return null
    }

    private fun createChild(treeUri: Uri, name: String): Uri =
        DocumentsContract.createDocument(
            contentResolver,
            treeDocumentUri(treeUri),
            "application/json",
            name,
        ) ?: throw FileNotFoundException("Unable to create $name")

    private fun deleteIfExists(treeUri: Uri, name: String) {
        findChild(treeUri, name)?.let { uri ->
            deleteDocument(uri, name)
        }
    }

    private fun deleteDocument(uri: Uri, name: String) {
        if (!DocumentsContract.deleteDocument(contentResolver, uri)) {
            throw FileNotFoundException("Unable to replace $name")
        }
    }

    private fun writeBytes(uri: Uri, bytes: ByteArray) {
        contentResolver.openOutputStream(uri, "wt")?.use { output ->
            output.write(bytes)
            output.flush()
        } ?: throw FileNotFoundException(uri.toString())
    }

    private fun copyDocument(source: Uri, target: Uri) {
        contentResolver.openInputStream(source)?.use { input ->
            contentResolver.openOutputStream(target, "wt")?.use { output ->
                input.copyTo(output)
                output.flush()
            } ?: throw FileNotFoundException(target.toString())
        } ?: throw FileNotFoundException(source.toString())
    }

    private fun replaceByCopy(treeUri: Uri, source: Uri, targetName: String): Uri {
        deleteIfExists(treeUri, targetName)
        val target = createChild(treeUri, targetName)
        copyDocument(source, target)
        return target
    }

    private fun renameOrCopy(treeUri: Uri, source: Uri, targetName: String): Uri {
        val renamed = runCatching {
            DocumentsContract.renameDocument(contentResolver, source, targetName)
        }.getOrNull()
        if (renamed != null) return renamed
        return replaceByCopy(treeUri, source, targetName).also {
            deleteDocument(source, targetName)
        }
    }

    private fun writeBackup(
        treeUri: Uri,
        targetName: String,
        previousName: String,
        bytes: ByteArray,
    ) {
        val temporaryName = "$targetName.tmp"
        deleteIfExists(treeUri, temporaryName)
        val temporary = createChild(treeUri, temporaryName)
        writeBytes(temporary, bytes)

        val current = findChild(treeUri, targetName)
        deleteIfExists(treeUri, previousName)
        if (current != null) renameOrCopy(treeUri, current, previousName)

        try {
            renameOrCopy(treeUri, temporary, targetName)
        } catch (error: Exception) {
            if (findChild(treeUri, targetName) == null) {
                findChild(treeUri, previousName)?.let { previous ->
                    replaceByCopy(treeUri, previous, targetName)
                }
            }
            throw error
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (AndroidHelper.isFoldable) {
            AndroidHelper.ToDart.onConfigurationChanged?.run()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        AndroidHelper.ToDart.onUserLeaveHint?.run()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration?) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidHelper.isPipMode = isInPictureInPictureMode
    }

    override fun onDestroy() {
        directoryPickerResult?.error("ACTIVITY_DESTROYED", "Activity was destroyed", null)
        directoryPickerResult = null
        backupExecutor.shutdown()
        super.onDestroy()
    }
}
