package gaming.kraftwerk.strom.runtime;

import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.Context;
import android.database.Cursor;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.provider.MediaStore;
import android.util.Log;

import java.io.File;
import java.io.IOException;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Names a file in shared storage with a {@code content:} URI.
 *
 * <p>Needed because a runtime app may want the payload as a URI rather
 * than a path, and an app targeting SDK 24 or later throws
 * FileUriExposedException the moment it puts a {@code file:} URI in an
 * intent bound for another process.
 *
 * <p>MediaStore is used rather than a FileProvider on purpose. A
 * FileProvider is configured through an XML resource, and this APK has no
 * resource tree at all; the payload is in public Downloads, which
 * MediaStore already indexes, so there is nothing to declare.
 */
final class MediaStoreUri {
    private static final String TAG = "strom";
    private static final long SCAN_TIMEOUT_MS = 15000;

    private MediaStoreUri() {
    }

    /**
     * @return a content URI for {@code file}, indexing it first if
     *         MediaStore has not seen it yet
     */
    static Uri of(Context c, File file) throws IOException {
        Uri known = lookup(c, file);
        if (known != null) {
            return known;
        }
        // Written with plain file I/O, so MediaStore has no row for it yet.
        Uri scanned = scan(c, file);
        if (scanned != null) {
            return scanned;
        }
        Uri retry = lookup(c, file);
        if (retry != null) {
            return retry;
        }
        throw new IOException("MediaStore will not name " + file
            + "; cannot hand it to another app as a content URI");
    }

    private static Uri lookup(Context c, File file) {
        ContentResolver cr = c.getContentResolver();
        Uri table = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL);
        Cursor cur = null;
        try {
            cur = cr.query(table, new String[] { MediaStore.MediaColumns._ID },
                MediaStore.MediaColumns.DATA + "=?",
                new String[] { file.getAbsolutePath() }, null);
            if (cur != null && cur.moveToFirst()) {
                return ContentUris.withAppendedId(table, cur.getLong(0));
            }
        } catch (Exception e) {
            Log.w(TAG, "MediaStore lookup failed for " + file, e);
        } finally {
            if (cur != null) {
                cur.close();
            }
        }
        return null;
    }

    /** Ask the media scanner to index the file, and wait for its answer. */
    private static Uri scan(Context c, File file) {
        final CountDownLatch done = new CountDownLatch(1);
        final AtomicReference<Uri> out = new AtomicReference<Uri>();
        MediaScannerConnection.scanFile(c, new String[] { file.getAbsolutePath() },
            new String[] { "application/octet-stream" },
            new MediaScannerConnection.OnScanCompletedListener() {
                @Override
                public void onScanCompleted(String path, Uri uri) {
                    out.set(uri);
                    done.countDown();
                }
            });
        try {
            if (!done.await(SCAN_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                Log.w(TAG, "media scan of " + file + " timed out");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return out.get();
    }
}
