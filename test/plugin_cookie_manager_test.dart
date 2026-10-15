import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';

void main() {
  test(
    'reads current browser cookies for the requested URL, including logout',
    () async {
      var browserCookies = 'session=secret; token=a=b';
      final requested = <Uri>[];
      final manager = PluginCookieManager(
        browserCookieReader: (uri) async {
          requested.add(uri);
          return browserCookies;
        },
      );
      await manager.saveFromWebView(
        'site',
        'https://www.cycani.org/',
        'old=stale',
      );
      await manager.saveLoginSession(
        'site',
        'https://www.cycani.org/',
        'browser-ua',
      );
      final headers = await manager.headersFor(
        'site',
        'https://www.cycani.org/play/1',
        {'user-agent': 'rule-ua', 'referer': 'https://www.cycani.org/'},
      );
      expect(headers['cookie'], 'session=secret; token=a=b');
      expect(headers['user-agent'], 'browser-ua');
      expect(headers['referer'], 'https://www.cycani.org/');
      expect(requested.single.path, '/play/1');
      browserCookies = '';
      expect(await manager.loadForRequest('site', requested.single), isEmpty);
    },
  );

  test(
    'does not send another rule or another website the login cookies',
    () async {
      var reads = 0;
      final manager = PluginCookieManager(
        browserCookieReader: (_) async {
          reads++;
          return 'session=private';
        },
      );
      await manager.saveLoginSession('site', 'https://www.cycani.org/', 'ua');
      for (final url in [
        'https://www.cycani.org.evil.test/',
        'https://other-cycani.org/',
        'https://cdn.example.org/video.mp4',
        'file:///etc/passwd',
      ]) {
        expect(await manager.loadForRequest('site', Uri.parse(url)), isEmpty);
      }
      expect(
        await manager.loadForRequest(
          'other rule',
          Uri.parse('https://www.cycani.org/'),
        ),
        isEmpty,
      );
      expect(reads, 0);
    },
  );

  test(
    'restores site registration without persisting authentication secrets',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kazumi-sessions-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final manager = PluginCookieManager();
      await manager.init(directory);
      await manager.saveLoginSession(
        'site',
        'https://www.cycani.org/',
        'browser-ua',
      );
      final file = File('${directory.path}/website_sessions.json');
      final data = jsonDecode(await file.readAsString());
      expect(data, {
        'site': {'site': 'https://www.cycani.org/', 'userAgent': 'browser-ua'},
      });
      final restored = PluginCookieManager(
        browserCookieReader: (_) async => 'session=from-native-store',
      );
      await restored.init(directory);
      expect(restored.userAgentFor('site'), 'browser-ua');
      final cookies = await restored.loadForRequest(
        'site',
        Uri.parse('https://www.cycani.org/'),
      );
      expect(cookies.single.value, 'from-native-store');
    },
  );

  test(
    'keeps captcha cookies available for rules without saved login',
    () async {
      final manager = PluginCookieManager();
      await manager.saveFromWebView(
        'captcha',
        'https://example.org/search',
        'clearance=value',
        userAgent: 'captcha-ua',
      );
      final headers = await manager.headersFor(
        'captcha',
        'https://example.org/play',
        {},
      );
      expect(headers['cookie'], 'clearance=value');
      expect(headers['user-agent'], 'captcha-ua');
      expect(
        await manager.loadForRequest(
          'captcha',
          Uri.parse('https://elsewhere.org/'),
        ),
        isEmpty,
      );
    },
  );

  test('rejects non-web login URLs', () async {
    final manager = PluginCookieManager();
    await expectLater(
      manager.saveLoginSession('site', 'file:///tmp/site', 'ua'),
      throwsFormatException,
    );
  });
}
