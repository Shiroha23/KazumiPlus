import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/pages/settings/website_login_settings.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';

Plugin rule(String name, String url) => Plugin.fromTemplate()
  ..name = name
  ..baseUrl = url;

Widget page(
  PluginsController controller,
  PluginCookieManager manager, {
  required OpenWebsiteLogin openWebsite,
}) => MaterialApp(
  home: SettingsPaneScope(
    embedded: true,
    showBackButton: false,
    onBack: () {},
    child: WebsiteLoginSettingsPage(
      controller: controller,
      cookieManager: manager,
      openWebsite: openWebsite,
    ),
  ),
);

void main() {
  testWidgets('groups rules by website and preserves removed-rule sessions', (
    tester,
  ) async {
    final controller = PluginsController(pluginJsonWriter: (_) async {});
    await controller.updatePlugins([
      rule('旧规则', 'https://www.example.org/'),
      rule('新规则', 'https://example.org/'),
      rule('接口规则', 'https://api.example.org/'),
    ]);
    final manager = PluginCookieManager();
    await manager.saveLoginSession('https://www.example.org/', 'browser-ua');
    await manager.saveLoginSession('https://removed.org/', 'browser-ua');
    String? opened;
    await tester.pumpWidget(
      page(
        controller,
        manager,
        openWebsite: (_, url) async {
          opened = url;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录管理'), findsOneWidget);
    expect(find.text('example.org'), findsOneWidget);
    expect(find.text('api.example.org'), findsNothing);
    expect(find.textContaining('共用规则：旧规则、新规则、接口规则'), findsOneWidget);
    expect(find.text('removed.org'), findsOneWidget);
    expect(find.textContaining('暂无关联规则'), findsOneWidget);
    expect(find.text('已登录'), findsNothing);

    await tester.tap(find.text('登录 / 管理账号').first);
    await tester.pumpAndSettle();
    expect(opened, 'https://www.example.org/');

    await controller.removePlugins({'旧规则', '新规则', '接口规则'});
    await tester.pumpAndSettle();
    expect(find.text('example.org'), findsOneWidget);
    expect(find.textContaining('暂无关联规则'), findsNWidgets(2));
    expect(manager.savedSites, hasLength(2));

    await controller.updatePlugin(rule('重新导入', 'https://www.example.org/'));
    await tester.pumpAndSettle();
    expect(find.textContaining('共用规则：重新导入'), findsOneWidget);
    expect(
      manager.userAgentFor('重新导入', url: 'https://example.org/'),
      'browser-ua',
    );
  });

  testWidgets('saving updates the list and adding a site validates URLs', (
    tester,
  ) async {
    final controller = PluginsController(pluginJsonWriter: (_) async {});
    await controller.updatePlugin(rule('规则', 'https://example.org/'));
    final manager = PluginCookieManager();
    final opened = <String>[];
    await tester.pumpWidget(
      page(
        controller,
        manager,
        openWebsite: (_, url) async {
          opened.add(url);
          await manager.saveLoginSession(url, 'ua');
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未保存会话'), findsOneWidget);
    await tester.tap(find.text('登录 / 管理账号'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未保存会话'), findsNothing);
    expect(find.textContaining('已保存会话'), findsOneWidget);

    await tester.tap(find.byTooltip('添加网站'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'file:///tmp/site');
    await tester.tap(find.text('打开网站'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的网站地址'), findsOneWidget);
    expect(opened, hasLength(1));
    await tester.enterText(find.byType(TextField), 'added.org');
    await tester.tap(find.text('打开网站'));
    await tester.pumpAndSettle();
    expect(opened.last, 'https://added.org');
    expect(find.text('added.org'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow pane handles long names and cancelled dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PluginsController(pluginJsonWriter: (_) async {});
    await controller.updatePlugins([
      rule('很长的规则名称用于检查窄屏显示以及文本自动换行', 'https://example.org/'),
      rule('同站的第二条规则', 'https://www.example.org/'),
    ]);
    final manager = PluginCookieManager();
    await tester.pumpWidget(
      page(
        controller,
        manager,
        openWebsite: (_, _) async => throw StateError('must not open'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('example.org'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('添加网站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
