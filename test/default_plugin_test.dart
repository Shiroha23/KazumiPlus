import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/card/rule_card.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/pages/plugin_editor/plugin_view_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

Plugin rule(String name) => Plugin.fromTemplate()..name = name;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_default_rule_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = originalPaths;
    expect(
      directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
      isTrue,
    );
    expect(
      directory.uri.pathSegments.where((part) => part.isNotEmpty).last,
      startsWith('kazumi_default_rule_'),
    );
    await directory.delete(recursive: true);
  });

  test(
    'persists default across restarts without changing configured order',
    () async {
      final controller = PluginsController();
      await controller.init();
      await controller.updatePlugins([
        rule('first'),
        rule('preferred'),
        rule('last'),
      ]);
      await controller.setDefaultPlugin(controller.pluginList[1]);

      final restored = PluginsController();
      await restored.init();
      expect(restored.defaultPluginNames, ['preferred']);
      expect(restored.pluginList.map((p) => p.name), [
        'first',
        'preferred',
        'last',
      ]);
      expect(restored.defaultPlugins.single.name, 'preferred');
      expect(restored.pluginList[1].toJson(), isNot(contains('isDefault')));

      await restored.setDefaultPlugin(restored.pluginList.last);
      final multiple = PluginsController();
      await multiple.init();
      expect(multiple.defaultPluginNames, ['preferred', 'last']);

      await restored.setDefaultPlugin(rule('preferred'), enabled: false);
      await restored.setDefaultPlugin(rule('last'), enabled: false);
      final cleared = PluginsController();
      await cleared.init();
      expect(cleared.defaultPluginNames, isEmpty);
      expect(cleared.defaultPlugins, isEmpty);
      expect(cleared.pluginList.map((p) => p.name), [
        'first',
        'preferred',
        'last',
      ]);
    },
  );

  test(
    'keeps multiple defaults through updates and reorders their priority',
    () async {
      late List<dynamic> saved;
      final controller = PluginsController(
        pluginJsonWriter: (json) async {
          saved = jsonDecode(json) as List;
        },
      );
      await controller.updatePlugins([rule('one'), rule('two')]);
      await controller.setDefaultPlugin(controller.pluginList.first);
      await controller.setDefaultPlugin(controller.pluginList.last);
      await controller.updatePlugin(rule('TWO')..version = '2.0');
      await controller.onReorder(0, 1);

      expect(controller.defaultPluginNames, ['TWO', 'one']);
      expect(controller.defaultPlugins.first.version, '2.0');
      expect(saved.where((p) => p['isDefault'] == true).map((p) => p['name']), ['TWO', 'one']);
    },
  );

  test('queued reorder preserves a pending default change on disk', () async {
    late List<dynamic> saved;
    final controller = PluginsController(
      pluginJsonWriter: (json) async {
        saved = jsonDecode(json) as List;
      },
    );
    await controller.updatePlugins([rule('one'), rule('two')]);

    final setting = controller.setDefaultPlugin(controller.pluginList.last);
    final reordering = controller.onReorder(0, 1);
    await Future.wait([setting, reordering]);

    expect(controller.defaultPluginNames, ['two']);
    expect(saved.where((p) => p['isDefault'] == true).single['name'], 'two');
  });

  for (final batch in [false, true]) {
    test(
      '${batch ? 'batch' : 'single'} deletion clears the removed default',
      () async {
        final controller = PluginsController(pluginJsonWriter: (_) async {});
        await controller.updatePlugins([rule('one'), rule('two')]);
        await controller.setDefaultPlugin(controller.pluginList.first);
        await controller.setDefaultPlugin(controller.pluginList.last);
        if (batch) {
          await controller.removePlugins({'one'});
        } else {
          await controller.removePlugin(rule('ONE'));
        }
        await controller.updatePlugin(rule('one'));

        expect(controller.defaultPluginNames, ['two']);
        expect(controller.defaultPlugins.single.name, 'two');
        expect(controller.pluginList.map((p) => p.name), ['two', 'one']);
      },
    );
  }

  test('failed writes restore both default and installed rules', () async {
    var failWrites = false;
    final controller = PluginsController(
      pluginJsonWriter: (_) async {
        if (failWrites) throw const FileSystemException('write failed');
      },
      errorReporter: (_, _, _) {},
    );
    await controller.updatePlugins([rule('one'), rule('two')]);
    await controller.setDefaultPlugin(controller.pluginList.first);
    failWrites = true;

    await expectLater(
      controller.setDefaultPlugin(controller.pluginList.last),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.defaultPluginNames, ['one']);
    await expectLater(
      controller.setDefaultPlugin(rule('one'), enabled: false),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.defaultPluginNames, ['one']);
    await expectLater(
      controller.removePlugins({'one'}),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.defaultPluginNames, ['one']);
    expect(controller.pluginList.map((p) => p.name), ['one', 'two']);
  });

  test('cannot make an uninstalled rule the default', () async {
    var writes = 0;
    final controller = PluginsController(
      pluginJsonWriter: (_) async => writes++,
      errorReporter: (_, _, _) {},
    );
    await expectLater(
      controller.setDefaultPlugin(rule('missing')),
      throwsArgumentError,
    );
    expect(controller.defaultPluginNames, isEmpty);
    expect(writes, 0);
  });

  testWidgets('star buttons select and clear multiple defaults independently', (
    tester,
  ) async {
    final controller = PluginsController(
      catalogLoader: () async => [],
      pluginJsonWriter: (_) async {},
    );
    await controller.updatePlugins([rule('one'), rule('two')]);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPaneScope(
          embedded: true,
          showBackButton: false,
          onBack: () {},
          child: PluginViewPage(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final name in ['one', 'two']) {
      final button = find.descendant(
        of: find.widgetWithText(RuleCard, name),
        matching: find.byTooltip('设为默认规则'),
      );
      expect(tester.getCenter(button).dx,
          lessThan(tester.getCenter(find.byTooltip('$name 的更多操作')).dx));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.defaultPluginNames, ['one', if (name == 'two') 'two']);
      expect(
        find.descendant(
          of: find.widgetWithText(RuleCard, name),
          matching: find.text('默认规则'),
        ),
        findsOneWidget,
      );
      expect(find.text('默认规则'), findsNWidgets(name == 'one' ? 1 : 2));
    }

    await tester.tap(find.descendant(
      of: find.widgetWithText(RuleCard, 'two'),
      matching: find.byTooltip('取消默认规则'),
    ));
    await tester.pumpAndSettle();
    expect(controller.defaultPluginNames, ['one']);
    expect(find.text('默认规则'), findsOneWidget);
    await tester.tap(find.byTooltip('取消默认规则'));
    await tester.pumpAndSettle();
    expect(controller.defaultPluginNames, isEmpty);
    expect(find.text('默认规则'), findsNothing);
    await tester.tap(find.byTooltip('two 的更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('设为默认规则'), findsNothing);
    expect(find.text('取消默认规则'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}
