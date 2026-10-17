package com.example.kazumi

import android.webkit.WebStorage
import androidx.webkit.WebStorageCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Uses WebView's own site-data API, including HttpOnly cookies and storage. */
class WebsiteDataHandler : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "deleteAccountData") {
            result.notImplemented()
            return
        }
        val host = call.argument<String>("host")
        if (host.isNullOrBlank() || host.any { it.isWhitespace() || it in "/\\\"" }) {
            result.error("INVALID_ARGUMENT", "Invalid website host", null)
            return
        }
        try {
            if (!WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)) {
                result.error("UNSUPPORTED_WEBVIEW", "Update Android System WebView to delete website account data", null)
                return
            }
            WebStorageCompat.deleteBrowsingDataForSite(WebStorage.getInstance(), host) {
                result.success(null)
            }
        } catch (error: Exception) {
            result.error("DELETE_FAILED", "Website account data could not be completely deleted", null)
        }
    }
}
