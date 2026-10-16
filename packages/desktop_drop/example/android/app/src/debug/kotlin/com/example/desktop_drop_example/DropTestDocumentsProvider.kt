package com.example.desktop_drop_example

import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.Bitmap
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsProvider
import java.io.File

/** Debug-only DocumentsProvider fixture; access requires MANAGE_DOCUMENTS or a URI grant. */
class DropTestDocumentsProvider : DocumentsProvider() {
    private val columns = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_MIME_TYPE, Document.COLUMN_FLAGS, Document.COLUMN_SIZE)
    private val root: File get() = File(context!!.cacheDir, "drop_test_documents")

    override fun onCreate(): Boolean {
        File(root, "folder/nested").mkdirs()
        File(root, "notes.txt").writeText("hello text file")
        File(root, "folder/inside.txt").writeText("inside directory")
        File(root, "folder/nested/deep.txt").writeText("nested directory")
        File(root, "sample.png").outputStream().use {
            val image = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
            image.compress(Bitmap.CompressFormat.PNG, 100, it)
            image.recycle()
        }
        return true
    }

    private fun file(id: String): File {
        val file = File(root, id).canonicalFile
        check(file.path.startsWith(root.canonicalPath + File.separator)) { "Invalid document ID" }
        return file
    }

    private fun add(cursor: MatrixCursor, id: String) {
        val file = file(id)
        val mime = if (file.isDirectory) Document.MIME_TYPE_DIR
            else if (file.extension == "png") "image/png" else "text/plain"
        val values = mapOf<String, Any?>(Document.COLUMN_DOCUMENT_ID to id, Document.COLUMN_DISPLAY_NAME to file.name,
            Document.COLUMN_MIME_TYPE to mime, Document.COLUMN_FLAGS to 0, Document.COLUMN_SIZE to file.length())
        cursor.addRow(cursor.columnNames.map { values[it] }.toTypedArray())
    }

    override fun queryRoots(projection: Array<out String>?): Cursor = MatrixCursor(projection ?: emptyArray())
    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor =
        MatrixCursor(projection ?: columns).also { add(it, documentId) }

    override fun queryChildDocuments(parentDocumentId: String, projection: Array<out String>?, sortOrder: String?): Cursor =
        MatrixCursor(projection ?: columns).also { cursor ->
            file(parentDocumentId).listFiles()!!.sortedBy { it.name }.forEach {
                add(cursor, "$parentDocumentId/${it.name}")
            }
        }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
        val parent = file(parentDocumentId)
        val child = file(documentId)
        return child == parent || child.path.startsWith(parent.path + File.separator)
    }

    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor =
        ParcelFileDescriptor.open(file(documentId), ParcelFileDescriptor.MODE_READ_ONLY)
}
