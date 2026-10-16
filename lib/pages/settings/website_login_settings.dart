import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/pages/plugin_editor/website_login_page.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';

typedef OpenWebsiteLogin = Future<bool> Function(BuildContext, String);

class WebsiteLoginSettingsPage extends StatefulWidget {
  const WebsiteLoginSettingsPage({
    super.key,
    required this.controller,
    this.cookieManager,
    this.openWebsite = showWebsiteLoginForSite,
  });

  final PluginsController controller;
  final PluginCookieManager? cookieManager;
  final OpenWebsiteLogin openWebsite;

  @override
  State<WebsiteLoginSettingsPage> createState() =>
      _WebsiteLoginSettingsPageState();
}

class _WebsiteEntry {
  _WebsiteEntry(this.site, {this.saved = false});

  final Uri site;
  final bool saved;
  final List<String> rules = [];
}

class _WebsiteLoginSettingsPageState extends State<WebsiteLoginSettingsPage> {
  PluginCookieManager get _manager =>
      widget.cookieManager ?? PluginCookieManager.instance;
  bool _opening = false;

  List<_WebsiteEntry> _websites() {
    final entries = <String, _WebsiteEntry>{
      for (final session in _manager.savedSites)
        session.host: _WebsiteEntry(session.site, saved: true),
    };
    for (final plugin in widget.controller.pluginList) {
      final uri = Uri.tryParse(plugin.baseUrl);
      if (uri == null || !PluginCookieManager.isWebsiteUrl(uri)) continue;
      final site = _manager.sessionFor(uri)?.site ?? uri;
      final host = PluginCookieManager.siteHost(site);
      final entry = entries.putIfAbsent(host, () => _WebsiteEntry(site));
      entry.rules.add(plugin.name);
    }
    final sites = entries.values.toList()
      ..sort(
        (a, b) => PluginCookieManager.siteHost(
          a.site,
        ).compareTo(PluginCookieManager.siteHost(b.site)),
      );
    return sites;
  }

  Future<void> _open(Uri site) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.openWebsite(context, site.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _addWebsite() async {
    final site = await showDialog<Uri>(
      context: context,
      builder: (context) => const _WebsiteAddressDialog(),
    );
    if (site != null && mounted) await _open(site);
  }

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('登录管理'),
    actions: [
      IconButton(
        tooltip: '添加网站',
        onPressed: _opening ? null : _addWebsite,
        icon: const Icon(Icons.add_rounded),
      ),
    ],
    body: ListenableBuilder(
      listenable: _manager,
      builder: (context, _) => Observer(
        builder: (context) {
          final sites = _websites();
          return SettingsList(
            sections: [
              const Padding(
                padding: EdgeInsets.fromLTRB(32, 0, 32, 20),
                child: Text(
                  '同一网站的规则共用登录状态，新规则自动复用已有会话。'
                  '进入网站可登录、切换或退出账号，完成后点击“保存并返回”。'
                  '登录是否有效以网站显示为准。',
                ),
              ),
              if (sites.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('暂无网站。导入规则后会自动列出对应网站，也可点击右上角添加。'),
                ),
              for (final entry in sites)
                SettingsSection(
                  title: Text(PluginCookieManager.siteHost(entry.site)),
                  tiles: [
                    SettingsTile(
                      leading: Icons.account_circle_outlined,
                      title: const Text('登录 / 管理账号'),
                      description: Text(
                        [
                          entry.saved ? '已保存会话' : '尚未保存会话',
                          if (entry.rules.isEmpty)
                            '暂无关联规则'
                          else
                            '共用规则：${entry.rules.join('、')}',
                        ].join('\n'),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      enabled: !_opening,
                      onPressed: (_) => _open(entry.site),
                    ),
                  ],
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(32, 0, 32, 12),
                child: Text('删除规则会保留网站会话；在网站内退出账号会对同站规则一起生效。'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _WebsiteAddressDialog extends StatefulWidget {
  const _WebsiteAddressDialog();

  @override
  State<_WebsiteAddressDialog> createState() => _WebsiteAddressDialogState();
}

class _WebsiteAddressDialogState extends State<_WebsiteAddressDialog> {
  final _address = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _address.text.trim();
    final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
    if (value.isEmpty ||
        uri == null ||
        !PluginCookieManager.isWebsiteUrl(uri)) {
      setState(() => _error = '请输入有效的网站地址');
      return;
    }
    Navigator.of(context).pop(uri);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加网站'),
    content: TextField(
      controller: _address,
      autofocus: true,
      keyboardType: TextInputType.url,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: '网站地址',
        hintText: 'https://example.com',
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('打开网站')),
    ],
  );
}
