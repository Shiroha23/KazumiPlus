import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';

void main() {
  test(
    'new and renamed rules share live website cookies and browser UA',
    () async {
      var browserCookies = 'session=secret; token=a=b';
      final requested = <Uri>[];
      final manager = PluginCookieManager(
        browserCookieReader: (uri) async {
          requested.add(uri);
          return browserCookies;
        },
      );
      await manager.saveLoginSession('https://www.example.org/', 'browser-ua');
      for (final name in ['old rule', 'new rule', 'renamed rule']) {
        final headers = await manager.headersFor(
          name,
          'https://api.example.org/play/1',
          {'user-agent': 'rule-ua'},
        );
        expect(headers['cookie'], 'session=secret; token=a=b');
        expect(headers['user-agent'], 'browser-ua');
      }
      expect(requested.every((uri) => uri.host == 'api.example.org'), isTrue);
      expect(requested.every((uri) => uri.path == '/play/1'), isTrue);
      browserCookies = '';
      for (final name in ['old rule', 'new rule']) {
        expect(await manager.loadForRequest(name, requested.first), isEmpty);
      }
    },
  );

  test(
    'never reads login cookies or browser UA for unrelated targets',
    () async {
      var reads = 0;
      final manager = PluginCookieManager(
        browserCookieReader: (_) async {
          reads++;
          return 'session=private';
        },
      );
      await manager.saveLoginSession('https://www.example.org/', 'browser-ua');
      for (final url in [
        'https://www.example.org.evil.test/',
        'https://other-example.org/',
        'https://another.org/',
        'https://cdn.example.net/video.mp4',
        'file:///etc/passwd',
        'https://name:secret@example.org/',
      ]) {
        final headers = await manager.headersFor('new rule', url, {});
        expect(headers.containsKey('cookie'), isFalse, reason: url);
        expect(headers.containsKey('user-agent'), isFalse, reason: url);
      }
      expect(reads, 0);
    },
  );

  test(
    'browser reads use each exact target URL and do not copy cookies',
    () async {
      final manager = PluginCookieManager(
        browserCookieReader: (uri) async {
          return uri.host == 'api.example.org' ? 'api=only' : 'web=only';
        },
      );
      await manager.saveLoginSession('https://example.org/', 'ua');
      expect(
        (await manager.headersFor(
          'new',
          'https://api.example.org/a',
          {},
        ))['cookie'],
        'api=only',
      );
      expect(
        (await manager.headersFor(
          'new',
          'https://www.example.org/b',
          {},
        ))['cookie'],
        'web=only',
      );
      expect(
        (await manager.headersFor(
          'new',
          'https://example.net/v.mp4',
          {},
        ))['cookie'],
        isNull,
      );
    },
  );

  test(
    'persists websites without rule names, URL tokens or auth cookies',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kazumi-sessions-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final manager = PluginCookieManager();
      await manager.init(directory);
      await manager.saveLoginSession(
        'https://www.example.org/account?token=sensitive#private',
        'browser-ua',
      );
      final file = File('${directory.path}/website_sessions.json');
      expect(jsonDecode(await file.readAsString()), {
        'version': 2,
        'sites': [
          {'site': 'https://www.example.org/', 'userAgent': 'browser-ua'},
        ],
      });
      final restored = PluginCookieManager(
        browserCookieReader: (_) async => 'session=from-native-store',
      );
      await restored.init(directory);
      expect(
        restored.userAgentFor('new rule', url: 'https://example.org/'),
        'browser-ua',
      );
      expect(
        (await restored.loadForRequest(
          'new rule',
          Uri.parse('https://www.example.org/'),
        )).single.value,
        'from-native-store',
      );
    },
  );

  test(
    'migrates and deduplicates legacy registrations including removed rules',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kazumi-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/website_sessions.json');
      await file.writeAsString(
        jsonEncode({
          'deleted old rule': {
            'site': 'https://www.example.org/',
            'userAgent': 'ua',
          },
          'second rule': {'site': 'https://example.org/path', 'userAgent': ''},
          'other rule': {'site': 'https://other.org/', 'userAgent': 'other-ua'},
          'invalid': {'site': 'file:///tmp/website'},
          'malformed': 'skip',
        }),
      );
      final manager = PluginCookieManager(
        browserCookieReader: (_) async => 'session=existing-browser-session',
      );
      await manager.init(directory);
      expect(manager.savedSites.map((site) => site.host), [
        'example.org',
        'other.org',
      ]);
      expect(
        manager.userAgentFor('brand new', url: 'https://api.example.org'),
        'ua',
      );
      expect(
        (await manager.loadForRequest(
          'brand new',
          Uri.parse('https://api.example.org/play'),
        )).single.value,
        'existing-browser-session',
      );
      final data = jsonDecode(await file.readAsString()) as Map;
      expect(data['version'], 2);
      expect(data.containsKey('deleted old rule'), isFalse);
      expect((data['sites'] as List).length, 2);
    },
  );

  test(
    'www and root registrations deduplicate and keep latest browser UA',
    () async {
      final manager = PluginCookieManager();
      await manager.saveLoginSession('https://WWW.example.org/', 'first');
      await manager.saveLoginSession('https://example.org/', 'second');
      expect(manager.savedSites, hasLength(1));
      expect(
        manager.userAgentFor('new', url: 'https://www.example.org'),
        'second',
      );
    },
  );

  test(
    'prefers specific site and does not guess shared parent domains',
    () async {
      final manager = PluginCookieManager();
      await manager.saveLoginSession('https://example.org', 'root');
      await manager.saveLoginSession('https://member.example.org', 'member');
      await manager.saveLoginSession('https://alice.github.io', 'alice');
      await manager.saveLoginSession('https://alice.co.uk', 'alice-uk');
      expect(
        manager.userAgentFor('new', url: 'https://api.member.example.org'),
        'member',
      );
      expect(
        manager.userAgentFor('new', url: 'https://api.example.org'),
        'root',
      );
      expect(manager.sessionFor(Uri.parse('https://bob.github.io')), isNull);
      expect(manager.sessionFor(Uri.parse('https://bob.co.uk')), isNull);
      expect(manager.sessionFor(Uri.parse('https://api.github.io')), isNull);
    },
  );

  test(
    'captcha snapshots remain scoped to the original rule and target site',
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
          'new rule',
          Uri.parse('https://example.org'),
        ),
        isEmpty,
      );
      expect(
        await manager.headersFor('captcha', 'https://elsewhere.org', {}),
        isEmpty,
      );
    },
  );

  test(
    'logout cannot resurrect old captcha cookies from any same-site rule',
    () async {
      final manager = PluginCookieManager(browserCookieReader: (_) async => '');
      for (final name in ['first', 'second']) {
        await manager.saveFromWebView(
          name,
          'https://example.org',
          'stale=token',
          userAgent: 'old-ua',
        );
      }
      await manager.saveLoginSession('https://example.org', 'browser-ua');
      for (final name in ['first', 'second', 'brand new']) {
        expect(
          await manager.loadForRequest(name, Uri.parse('https://example.org')),
          isEmpty,
        );
      }
      // Even if browser access is unavailable, never fall back to stale snapshots.
      manager.browserCookieReader = null;
      expect(
        await manager.loadForRequest('first', Uri.parse('https://example.org')),
        isEmpty,
      );
    },
  );

  test(
    'website saves and deletion persist independently and notify observers',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kazumi-concurrent-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final cleaned = <String>[];
      final manager = PluginCookieManager(
        browserDataCleaner: (site, origins) async {
          cleaned.add(site.host);
        },
      );
      await manager.init(directory);
      var changes = 0;
      manager.addListener(() => changes++);
      await Future.wait([
        manager.saveLoginSession('https://first.org', 'ua1'),
        manager.saveLoginSession('https://second.org', 'ua2'),
      ]);
      final restored = PluginCookieManager();
      await restored.init(directory);
      expect(restored.savedSites, hasLength(2));
      expect(changes, 2);

      await manager.saveFromWebView(
        'old rule',
        'https://first.org/',
        'stale=token',
      );
      await manager.deleteAccountData('https://www.first.org/');
      expect(cleaned, ['first.org']);
      expect(changes, 3);
      expect(manager.savedSites.single.host, 'second.org');
      expect(
        await manager.headersFor('old rule', 'https://first.org/play', {}),
        isEmpty,
      );
      expect(
        manager.userAgentFor('new rule', url: 'https://first.org'),
        isNull,
      );
      final afterDeletion = PluginCookieManager();
      await afterDeletion.init(directory);
      expect(afterDeletion.savedSites.single.host, 'second.org');
    },
  );

  test('rejects non-web login URLs and URLs containing credentials', () async {
    final manager = PluginCookieManager();
    for (final url in [
      'file:///tmp/site',
      'https://user:secret@example.org/',
    ]) {
      await expectLater(
        manager.saveLoginSession(url, 'ua'),
        throwsFormatException,
      );
    }
  });

  test(
    'failed browser deletion preserves registration and reports failure',
    () async {
      final manager = PluginCookieManager(
        browserDataCleaner: (_, _) async {
          throw StateError('native deletion failed');
        },
      );
      await manager.saveLoginSession(
        'https://example.org',
        'ua',
        origins: [
          'https://api.example.org/account?secret=not-persisted',
          'https://other.org',
        ],
      );
      expect(manager.savedSites.single.origins, ['https://api.example.org']);
      await manager.saveLoginSession('https://example.org:8443', 'ua');
      expect(manager.savedSites.single.origins, [
        'https://example.org',
        'https://api.example.org',
      ]);
      await expectLater(
        manager.deleteAccountData('https://example.org'),
        throwsStateError,
      );
      expect(manager.savedSites.single.host, 'example.org');
      expect(manager.userAgentFor('rule', url: 'https://example.org'), 'ua');
    },
  );
}
