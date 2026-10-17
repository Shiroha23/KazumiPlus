import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart' as linux;
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
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
  static const _dataChannel = MethodChannel('com.predidit.kazumi/website_data');
  static final _deletions = AsyncSerialQueue();
  static int accountDataGeneration = 0;

  /// Delete native browser data for this website, including HttpOnly cookies.
  /// Never fall back to clearing every website or document.cookie JavaScript.
  static Future<void> clearSiteData(Uri site, List<String> visitedOrigins) =>
      _deletions.run(() async {
        if (!PluginCookieManager.isWebsiteUrl(site)) {
          throw const FormatException('无效的网站地址');
        }
        final host = PluginCookieManager.siteHost(site);
        final origins = <String>{site.origin};
        for (final value in visitedOrigins) {
          final uri = Uri.tryParse(value);
          if (uri != null && PluginCookieManager.isSiteHost(site, uri)) {
            origins.add(uri.origin);
          }
        }
        if (Platform.isMacOS || Platform.isIOS) {
          final storage = PlatformWebStorageManager(
            const PlatformWebStorageManagerCreationParams(),
          );
          final records = await storage.fetchDataRecords(
            dataTypes: WebsiteDataType.ALL,
          );
          final matching = records.where((record) {
            final name = record.displayName;
            if (name == null || name.isEmpty) return false;
            final uri = Uri.tryParse('https://$name');
            // WebKit groups records using its public suffix list.
            return uri != null &&
                (PluginCookieManager.isSiteHost(site, uri) ||
                    PluginCookieManager.isSiteHost(uri, site));
          }).toList();
          if (matching.isNotEmpty) {
            await storage.removeDataFor(
              dataTypes: WebsiteDataType.ALL,
              dataRecords: matching,
            );
          }
        } else {
          Future<void> nativeClear() async {
            final proxy =
                Platform.isWindows &&
                    GStorage.getSetting(SettingsKeys.proxyEnable)
                ? ProxyUtils.getFormattedProxyUrl(
                    GStorage.getSetting(SettingsKeys.proxyUrl),
                  )
                : null;
            await _dataChannel.invokeMethod<void>('deleteAccountData', {
              'host': host,
              'origins': origins.toList(),
              if (proxy != null) 'additionalArguments': '--proxy-server=$proxy',
            });
          }

          if (Platform.isWindows) {
            final reader = _windowsCookies;
            _windowsCookies = null;
            if (reader != null) await (await reader).dispose();
            await nativeClear();
          } else if (Platform.isLinux) {
            await _linuxReads.run(() async {
              final reader = _linuxCookies;
              _linuxCookies = null;
              _linuxOrigin = null;
              if (reader != null) (await reader).close();
              await nativeClear();
            });
          } else if (Platform.isAndroid) {
            await nativeClear();
          } else {
            throw UnsupportedError('当前平台尚不支持按网站删除账号信息');
          }
        }
        accountDataGeneration++;
      });

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
