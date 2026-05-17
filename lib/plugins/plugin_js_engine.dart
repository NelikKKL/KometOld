import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import 'plugin_model.dart';
import 'plugin_permissions.dart';
import 'plugin_chat_hooks.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Событие от JS-скрипта плагина → хосту (Dart)
// ─────────────────────────────────────────────────────────────────────────────

class PluginJsEvent {
  final String pluginId;
  final String type;
  final Map<String, dynamic> payload;

  const PluginJsEvent({
    required this.pluginId,
    required this.type,
    required this.payload,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Одна «виртуальная машина» для одного плагина
// ─────────────────────────────────────────────────────────────────────────────

class _PluginJsRuntime {
  final String pluginId;
  final String scriptPath;
  final PluginPermissionsStore _perms;
  final void Function(PluginJsEvent) _onEvent;

  HeadlessInAppWebView? _headless;
  InAppWebViewController? _ctrl;
  bool _ready = false;

  /// Очередь вызовов, пришедших до готовности WebView
  final List<_PendingCall> _queue = [];

  _PluginJsRuntime({
    required this.pluginId,
    required this.scriptPath,
    required PluginPermissionsStore perms,
    required void Function(PluginJsEvent) onEvent,
  })  : _perms = perms,
        _onEvent = onEvent;

  // ──────────────────────────────────────────────
  // Запуск
  // ──────────────────────────────────────────────

  Future<void> start() async {
    final scriptContent = await File(scriptPath).readAsString();
    final bootstrapHtml = _buildBootstrapHtml(scriptContent);

    _headless = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(data: bootstrapHtml),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: false,
        // Запрет сети — плагин не должен делать произвольные запросы
        blockNetworkImage: false,
      ),
      onWebViewCreated: (ctrl) {
        _ctrl = ctrl;

        // Канал: JS → Dart
        ctrl.addJavaScriptHandler(
          handlerName: '_kometBridge',
          callback: _handleJsMessage,
        );
      },
      onLoadStop: (ctrl, url) async {
        _ready = true;
        for (final call in _queue) {
          await _evalQueued(call);
        }
        _queue.clear();
        debugPrint('[PluginJS] Plugin "$pluginId" runtime ready');
      },
      onConsoleMessage: (ctrl, msg) {
        debugPrint('[PluginJS][$pluginId] ${msg.messageLevel.toValue()}: ${msg.message}');
      },
      onReceivedError: (ctrl, req, err) {
        debugPrint('[PluginJS][$pluginId] Error: ${err.description}');
      },
    );

    await _headless!.run();
  }

  // ──────────────────────────────────────────────
  // Bootstrap HTML / JS — внедряет API komet.*
  // ──────────────────────────────────────────────

  String _buildBootstrapHtml(String userScript) {
    return '''<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body>
<script>
// ── Komet Plugin API ──────────────────────────────────────────────────────────

const _komet_callId_map = {};
let _komet_callId = 0;

function _send(type, payload) {
  window.flutter_inappwebview.callHandler('_kometBridge', JSON.stringify({ type, payload }));
}

function _call(method, args) {
  return new Promise((resolve, reject) => {
    const id = ++_komet_callId;
    _komet_callId_map[id] = { resolve, reject };
    _send('call', { id, method, args });
  });
}

// Ответы на вызовы: Dart → JS
window._kometResolve = function(id, result) {
  const p = _komet_callId_map[id];
  if (p) { delete _komet_callId_map[id]; p.resolve(result); }
};
window._kometReject = function(id, error) {
  const p = _komet_callId_map[id];
  if (p) { delete _komet_callId_map[id]; p.reject(new Error(error)); }
};

// Входящие события: Dart → JS (новое сообщение, смена чата и т.д.)
const _eventListeners = {};
window._kometDispatchEvent = function(type, data) {
  (_eventListeners[type] || []).forEach(fn => { try { fn(data); } catch(e) {} });
};

const komet = {
  // ── Утилиты ────────────────────────────────────────────────────────────────
  log: (...args) => _send('log', { message: args.join(' ') }),

  // ── Хранилище плагина ──────────────────────────────────────────────────────
  storage: {
    get: (key) => _call('storage.get', { key }),
    set: (key, value) => _call('storage.set', { key, value }),
    remove: (key) => _call('storage.remove', { key }),
    keys: () => _call('storage.keys', {}),
  },

  // ── Чаты ──────────────────────────────────────────────────────────────────
  chats: {
    list: () => _call('chats.list', {}),
    getMessages: (chatId, limit) => _call('chats.getMessages', { chatId, limit: limit || 20 }),
  },

  // ── Профиль ───────────────────────────────────────────────────────────────
  profile: {
    getSelf: () => _call('profile.getSelf', {}),
  },

  // ── Перехват сообщений ────────────────────────────────────────────────────
  messages: {
    onOutgoing: (fn) => { _eventListeners['outgoing'] = [fn]; },
    onIncoming: (fn) => { _eventListeners['incoming'] = [fn]; },
  },

  // ── Меню чата ─────────────────────────────────────────────────────────────
  chatMenu: {
    addItem: (id, label, iconName) => _call('chatMenu.addItem', { id, label, iconName }),
  },

  // ── Уведомления ──────────────────────────────────────────────────────────
  notify: (title, body) => _send('notify', { title, body }),

  // ── События ──────────────────────────────────────────────────────────────
  on: (event, fn) => {
    _eventListeners[event] = _eventListeners[event] || [];
    _eventListeners[event].push(fn);
  },
  off: (event, fn) => {
    if (_eventListeners[event]) {
      _eventListeners[event] = _eventListeners[event].filter(f => f !== fn);
    }
  },
};

// ── Пользовательский скрипт ───────────────────────────────────────────────────
try {
  (function() {
${userScript}
  })();
} catch (e) {
  _send('error', { message: e.message, stack: e.stack });
}
</script>
</body>
</html>''';
  }

  // ──────────────────────────────────────────────
  // Обработка сообщений JS → Dart
  // ──────────────────────────────────────────────

  dynamic _handleJsMessage(List<dynamic> args) {
    if (args.isEmpty) return null;
    try {
      final raw = args.first as String;
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final type = msg['type'] as String;
      final payload = (msg['payload'] as Map<String, dynamic>?) ?? {};

      switch (type) {
        case 'log':
          debugPrint('[PluginJS:log][$pluginId] ${payload['message']}');
          break;
        case 'error':
          debugPrint('[PluginJS:error][$pluginId] ${payload['message']}\n${payload['stack']}');
          break;
        case 'notify':
          _onEvent(PluginJsEvent(pluginId: pluginId, type: 'notify', payload: payload));
          break;
        case 'call':
          _handleApiCall(payload);
          break;
        default:
          _onEvent(PluginJsEvent(pluginId: pluginId, type: type, payload: payload));
      }
    } catch (e) {
      debugPrint('[PluginJS][$pluginId] Bridge error: $e');
    }
    return null;
  }

  // ──────────────────────────────────────────────
  // Маршрутизация API-вызовов из JS
  // ──────────────────────────────────────────────

  Future<void> _handleApiCall(Map<String, dynamic> payload) async {
    final id = payload['id'] as int;
    final method = payload['method'] as String;
    final args = (payload['args'] as Map<String, dynamic>?) ?? {};

    try {
      final result = await _dispatchApiCall(method, args);
      await _resolveCall(id, result);
    } catch (e) {
      await _rejectCall(id, e.toString());
    }
  }

  Future<dynamic> _dispatchApiCall(String method, Map<String, dynamic> args) async {
    switch (method) {
      case 'storage.get':
        return _storageGet(args['key'] as String);
      case 'storage.set':
        _storageSet(args['key'] as String, args['value']);
        return true;
      case 'storage.remove':
        _storageRemove(args['key'] as String);
        return true;
      case 'storage.keys':
        return _storageKeys();
      case 'chats.list':
        _requirePermission(PluginPermission.readChats);
        _onEvent(PluginJsEvent(pluginId: pluginId, type: 'api.chats.list', payload: {'callId': args['_callId']}));
        return <dynamic>[];
      case 'profile.getSelf':
        _requirePermission(PluginPermission.readSelfProfile);
        _onEvent(PluginJsEvent(pluginId: pluginId, type: 'api.profile.getSelf', payload: {}));
        return <String, dynamic>{};
      case 'chatMenu.addItem':
        _requirePermission(PluginPermission.addChatMenuItems);
        _onEvent(PluginJsEvent(pluginId: pluginId, type: 'api.chatMenu.addItem', payload: args));
        return true;
      default:
        throw Exception('Unknown API method: $method');
    }
  }

  void _requirePermission(PluginPermission perm) {
    if (!_perms.isGranted(pluginId, perm)) {
      throw Exception('Permission denied: ${perm.name}');
    }
  }

  // ──────────────────────────────────────────────
  // Простое in-memory хранилище (SharedPreferences через PluginService)
  // ──────────────────────────────────────────────

  final Map<String, dynamic> _storage = {};

  dynamic _storageGet(String key) => _storage[key];
  void _storageSet(String key, dynamic value) => _storage[key] = value;
  void _storageRemove(String key) => _storage.remove(key);
  List<String> _storageKeys() => _storage.keys.toList();

  // ──────────────────────────────────────────────
  // Resolve / Reject промисов в JS
  // ──────────────────────────────────────────────

  Future<void> _resolveCall(int id, dynamic result) async {
    final encoded = jsonEncode(result);
    await _ctrl?.evaluateJavascript(source: 'window._kometResolve($id, $encoded);');
  }

  Future<void> _rejectCall(int id, String error) async {
    final escaped = jsonEncode(error);
    await _ctrl?.evaluateJavascript(source: 'window._kometReject($id, $escaped);');
  }

  // ──────────────────────────────────────────────
  // Отправка событий в JS (вызывается из Dart)
  // ──────────────────────────────────────────────

  Future<void> dispatchEvent(String type, Map<String, dynamic> data) async {
    if (!_ready) {
      _queue.add(_PendingCall(type: type, data: data));
      return;
    }
    final encoded = jsonEncode(data);
    await _ctrl?.evaluateJavascript(
      source: 'window._kometDispatchEvent(${jsonEncode(type)}, $encoded);',
    );
  }

  Future<void> _evalQueued(_PendingCall call) async {
    final encoded = jsonEncode(call.data);
    await _ctrl?.evaluateJavascript(
      source: 'window._kometDispatchEvent(${jsonEncode(call.type)}, $encoded);',
    );
  }

  // ──────────────────────────────────────────────
  // Остановка
  // ──────────────────────────────────────────────

  Future<void> stop() async {
    _ready = false;
    await _headless?.dispose();
    _headless = null;
    _ctrl = null;
  }
}

class _PendingCall {
  final String type;
  final Map<String, dynamic> data;
  _PendingCall({required this.type, required this.data});
}

// ─────────────────────────────────────────────────────────────────────────────
// Менеджер JS-движков для всех плагинов — синглтон
// ─────────────────────────────────────────────────────────────────────────────

class PluginJsEngine {
  static final PluginJsEngine _instance = PluginJsEngine._internal();
  factory PluginJsEngine() => _instance;
  PluginJsEngine._internal();

  final Map<String, _PluginJsRuntime> _runtimes = {};
  final PluginPermissionsStore _perms = PluginPermissionsStore();

  final StreamController<PluginJsEvent> _events =
      StreamController<PluginJsEvent>.broadcast();

  /// Поток всех событий от JS-плагинов
  Stream<PluginJsEvent> get events => _events.stream;

  // ──────────────────────────────────────────────
  // Запуск плагина
  // ──────────────────────────────────────────────

  Future<void> startPlugin(KometPlugin plugin) async {
    if (plugin.scriptPath == null) return;
    if (_runtimes.containsKey(plugin.id)) return; // уже запущен

    // flutter_inappwebview требует Android API 19+, iOS 9+
    if (!Platform.isAndroid && !Platform.isIOS) {
      debugPrint('[PluginJsEngine] JS plugins not supported on this platform');
      return;
    }

    await _perms.load();

    final runtime = _PluginJsRuntime(
      pluginId: plugin.id,
      scriptPath: plugin.scriptPath!,
      perms: _perms,
      onEvent: _events.add,
    );

    _runtimes[plugin.id] = runtime;
    try {
      await runtime.start();
      debugPrint('[PluginJsEngine] Started JS runtime for "${plugin.id}"');
    } catch (e) {
      _runtimes.remove(plugin.id);
      debugPrint('[PluginJsEngine] Failed to start "${plugin.id}": $e');
    }
  }

  // ──────────────────────────────────────────────
  // Остановка плагина
  // ──────────────────────────────────────────────

  Future<void> stopPlugin(String pluginId) async {
    final rt = _runtimes.remove(pluginId);
    if (rt != null) {
      await rt.stop();
      debugPrint('[PluginJsEngine] Stopped JS runtime for "$pluginId"');
    }
  }

  // ──────────────────────────────────────────────
  // Рассылка событий во все (или конкретный) плагин
  // ──────────────────────────────────────────────

  Future<void> dispatchToPlugin(
    String pluginId,
    String type,
    Map<String, dynamic> data,
  ) async {
    await _runtimes[pluginId]?.dispatchEvent(type, data);
  }

  Future<void> broadcastEvent(String type, Map<String, dynamic> data) async {
    for (final rt in _runtimes.values) {
      await rt.dispatchEvent(type, data);
    }
  }

  // ──────────────────────────────────────────────
  // Запустить все включённые плагины со скриптом
  // ──────────────────────────────────────────────

  Future<void> startAll(List<KometPlugin> plugins) async {
    for (final plugin in plugins) {
      if (plugin.isEnabled && plugin.scriptPath != null) {
        await startPlugin(plugin);
      }
    }
  }

  Future<void> stopAll() async {
    for (final id in List.of(_runtimes.keys)) {
      await stopPlugin(id);
    }
  }

  bool isRunning(String pluginId) => _runtimes.containsKey(pluginId);
}
