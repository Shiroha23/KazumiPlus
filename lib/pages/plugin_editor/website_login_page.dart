import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart' as linux;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/error_widget.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/plugin_cookie_manager.dart';
import 'package:kazumi/webview/login/website_browser.dart';
import 'package:webview_windows/webview_windows.dart' as windows;

Future<bool> showWebsiteLogin(BuildContext context, Plugin plugin) async {
  return showWebsiteLoginForSite(context, plugin.baseUrl);
}

Future<bool> showWebsiteLoginForSite(
  BuildContext context,
  String siteUrl,
) async {
  final uri = Uri.tryParse(siteUrl);
  if (uri == null || !PluginCookieManager.isWebsiteUrl(uri)) {
    KazumiDialog.showToast(message: '网站地址无效，请检查 http 或 https 地址');
    return false;
  }
  return await Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute(builder: (_) => WebsiteLoginPage(siteUrl: siteUrl)),
      ) ??
      false;
}

class WebsiteLoginPage extends StatefulWidget {
  const WebsiteLoginPage({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<WebsiteLoginPage> createState() => _WebsiteLoginPageState();
}

class _WebsiteLoginPageState extends State<WebsiteLoginPage> {
  windows.WebviewController? _windows;
  linux.Webview? _linux;
  PlatformInAppWebViewController? _mobile;
  PlatformInAppWebViewWidget? _mobileWidget;
  final List<StreamSubscription> _subscriptions = [];
  final _address = TextEditingController();
  bool _ready = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final Set<String> _visitedOrigins = {};

  String get _siteHost =>
      PluginCookieManager.siteHost(Uri.parse(widget.siteUrl));

  @override
  void initState() {
    super.initState();
    _address.text = widget.siteUrl;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (Platform.isWindows) {
        await WebsiteBrowser.setupWindowsProxy();
        if (!mounted) return;
        final controller = windows.WebviewController();
        await controller.initialize();
        if (!mounted) {
          await controller.dispose();
          return;
        }
        _windows = controller;
        await controller.setPopupWindowPolicy(
          windows.WebviewPopupWindowPolicy.deny,
        );
        if (!mounted) return;
        _subscriptions.add(controller.url.listen(_updateAddress));
        _subscriptions.add(
          controller.loadingState.listen((state) {
            if (mounted) {
              setState(
                () => _loading =
                    state != windows.LoadingState.navigationCompleted,
              );
            }
          }),
        );
        setState(() => _ready = true);
        await controller.loadUrl(widget.siteUrl);
      } else if (Platform.isLinux) {
        final view = await linux.WebviewWindow.create(
          configuration: linux.CreateConfiguration(
            title: '$_siteHost · 网站登录',
            proxy: WebsiteBrowser.linuxProxy,
          ),
        );
        if (!mounted) {
          view.close();
          return;
        }
        _linux = view;
        view.setOnUrlRequestCallback((url) {
          _updateAddress(url);
          return true;
        });
        view.launch(widget.siteUrl);
        unawaited(
          view.onClose.then((_) {
            if (mounted) {
              setState(() {
                _linux = null;
                _ready = false;
                _error = '网站窗口已关闭，请返回后重新打开登录页面。';
              });
            }
          }),
        );
        setState(() {
          _ready = true;
          _loading = false;
        });
      } else {
        _mobileWidget = PlatformInAppWebViewWidget(
          PlatformInAppWebViewWidgetCreationParams(
            initialUrlRequest: URLRequest(url: WebUri(widget.siteUrl)),
            initialSettings: InAppWebViewSettings(
              // Keep the default persistent store shared with video parsing.
              sharedCookiesEnabled: true,
              thirdPartyCookiesEnabled: true,
              javaScriptCanOpenWindowsAutomatically: false,
            ),
            onWebViewCreated: (controller) {
              _mobile = controller;
              if (mounted) setState(() => _ready = true);
            },
            onLoadStart: (controller, url) {
              if (url != null) _updateAddress(url.toString());
              if (mounted) setState(() => _loading = true);
            },
            onLoadStop: (controller, url) {
              if (url != null) _updateAddress(url.toString());
              if (mounted) setState(() => _loading = false);
            },
            onUpdateVisitedHistory: (controller, url, isReload) {
              if (url != null) _updateAddress(url.toString());
            },
          ),
        );
        if (mounted) setState(() {});
      }
    } catch (error, stackTrace) {
      KazumiLogger().w(
        'Unable to open website login',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '无法打开登录页面，请检查网络和系统 WebView 后重试。';
        });
      }
    }
  }

  void _updateAddress(String url) {
    if (!mounted) return;
    final uri = Uri.tryParse(url);
    if (uri != null && PluginCookieManager.isWebsiteUrl(uri)) {
      _address.text = url;
      if (PluginCookieManager.isSiteHost(Uri.parse(widget.siteUrl), uri)) {
        _visitedOrigins.add(uri.origin);
      }
    }
  }

  Future<void> _navigate(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !PluginCookieManager.isWebsiteUrl(uri)) {
      KazumiDialog.showToast(message: '请输入完整的 http 或 https 网站地址');
      return;
    }
    try {
      await _windows?.loadUrl(uri.toString());
      _linux?.launch(uri.toString());
      await _mobile?.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri.toString())),
      );
    } catch (_) {
      KazumiDialog.showToast(message: '无法打开此地址，请重试');
    }
  }

  Future<void> _save() async {
    if (!_ready || _saving) return;
    setState(() => _saving = true);
    try {
      final dynamic result;
      if (_windows != null) {
        result = await _windows!.executeScript('navigator.userAgent');
      } else if (_linux != null) {
        result = await _linux!.evaluateJavaScript('navigator.userAgent');
      } else {
        result = await _mobile!.evaluateJavascript(
          source: 'navigator.userAgent',
        );
      }
      await PluginCookieManager.instance.saveLoginSession(
        widget.siteUrl,
        result?.toString() ?? '',
        origins: _visitedOrigins,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      KazumiLogger().w(
        'Unable to save website session',
        error: error,
        stackTrace: stackTrace,
      );
      KazumiDialog.showToast(message: '保存网站会话失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_windows?.dispose());
    _linux?.close();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('$_siteHost · 网站登录'),
      actions: [
        TextButton(
          onPressed: _ready && !_saving ? _save : null,
          child: Text(_saving ? '保存中…' : '保存并返回'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _address,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: _ready ? _navigate : null,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: '网站地址',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '打开地址',
                  onPressed: _ready ? () => _navigate(_address.text) : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                IconButton(
                  tooltip: '网站首页',
                  onPressed: _ready ? () => _navigate(widget.siteUrl) : null,
                  icon: const Icon(Icons.home_outlined),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '登录、切换或退出账号后，点击“保存并返回”。同站规则自动共用此会话，退出账号会对同站规则一起生效。登录是否有效请以网站显示为准。',
            ),
          ),
          if (_loading && _error == null) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? GeneralErrorWidget(errMsg: _error!)
                : Platform.isWindows && _ready
                ? windows.Webview(_windows!)
                : Platform.isLinux
                ? Center(
                    child: FilledButton.icon(
                      onPressed: () => _linux?.bringToForeground(),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('前往网站窗口登录'),
                    ),
                  )
                : _mobileWidget?.build(context) ?? const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}
