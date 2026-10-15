import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart' as linux;
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:webview_windows/webview_windows.dart' as windows;

/// Login and video parsing use each platform's default persistent browser store,
/// so localStorage authentication works without extracting website tokens.
class WebsiteBrowser {
  static Future<windows.HeadlessWebview>? _windowsCookies;
  static Future<linux.Webview>? _linuxCookies;
  static final _linuxReads = AsyncSerialQueue();
  static String? _linuxOrigin;

  static linux.ProxyConfiguration? get linuxProxy {
    if (!GStorage.getSetting(SettingsKeys.proxyEnable)) return null;
    final proxy = ProxyUtils.parseProxyUrl(
      GStorage.getSetting(SettingsKeys.proxyUrl),
    );
    if (proxy == null) return null;
    return linux.ProxyConfiguration(host: proxy.$1, port: proxy.$2);
  }

  static Future<void> setupWindowsProxy() async {
    if (!GStorage.getSetting(SettingsKeys.proxyEnable)) return;
    final proxy = ProxyUtils.getFormattedProxyUrl(
      GStorage.getSetting(SettingsKeys.proxyUrl),
    );
    if (proxy == null) return;
    try {
      await windows.WebviewController.initializeEnvironment(
        additionalArguments: '--proxy-server=$proxy',
      );
    } catch (_) {
      // The parser may have already initialized the shared environment.
    }
  }

  static Future<windows.HeadlessWebview> _createWindowsCookieReader() async {
    await setupWindowsProxy();
    final view = windows.HeadlessWebview();
    await view.run();
    return view;
  }

  static Future<String> cookiesFor(Uri uri) async {
    if (Platform.isWindows) {
      try {
        final view = await (_windowsCookies ??= _createWindowsCookieReader());
        return await view.getCookies(uri.toString()) ?? '';
      } catch (_) {
        _windowsCookies = null;
        rethrow;
      }
    }
    if (Platform.isLinux) return _linuxReads.run(() => _linuxCookiesFor(uri));
    final cookies = await PlatformCookieManager(
      const PlatformCookieManagerCreationParams(),
    ).getCookies(url: WebUri(uri.toString()));
    return cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  static Future<String> _linuxCookiesFor(Uri uri) async {
    try {
      final view = await (_linuxCookies ??= linux.WebviewWindow.create(
        configuration: linux.CreateConfiguration(
          headless: true,
          proxy: linuxProxy,
        ),
      ));
      // This plugin's getAllCookies actually reads cookies for the current
      // document URI. Load the origin once, then use the same-origin History
      // API to select the request path without loading a video or API endpoint.
      if (_linuxOrigin != uri.origin) {
        final loaded = Completer<void>();
        var started = false;
        void onNavigation() {
          if (view.isNavigating.value) started = true;
          if (started && !view.isNavigating.value && !loaded.isCompleted) {
            loaded.complete();
          }
        }

        view.isNavigating.addListener(onNavigation);
        try {
          view.launch('${uri.origin}/');
          await loaded.future.timeout(const Duration(seconds: 10));
        } finally {
          view.isNavigating.removeListener(onNavigation);
        }
        _linuxOrigin = uri.origin;
      }
      await view.evaluateJavaScript(
        'history.replaceState(null, "", ${jsonEncode(uri.toString())});',
      );
      final cookies = await view.getAllCookies();
      final now = DateTime.now();
      return cookies
          .where((cookie) {
            final domain = cookie.domain.replaceFirst(RegExp(r'^\.'), '');
            final domainMatches =
                uri.host == domain ||
                (cookie.domain.startsWith('.') &&
                    uri.host.endsWith('.$domain'));
            final path = cookie.path.isEmpty ? '/' : cookie.path;
            final requestPath = uri.path.isEmpty ? '/' : uri.path;
            final pathMatches =
                requestPath == path ||
                (requestPath.startsWith(path) &&
                    (path.endsWith('/') ||
                        requestPath.substring(path.length).startsWith('/')));
            return domainMatches &&
                pathMatches &&
                (!cookie.secure || uri.scheme == 'https') &&
                (cookie.sessionOnly ||
                    cookie.expires == null ||
                    cookie.expires!.isAfter(now));
          })
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
    } catch (_) {
      _linuxOrigin = null;
      rethrow;
    }
  }
}
