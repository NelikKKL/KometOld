import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gwid/plugins/plugin_permissions.dart';
import 'package:gwid/plugins/plugin_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Результат перехвата сообщения
// ─────────────────────────────────────────────────────────────────────────────

enum MessageInterceptAction {
  /// Пропустить сообщение без изменений
  passthrough,

  /// Заменить текст сообщения
  replace,

  /// Заблокировать отправку / отображение сообщения
  block,
}

class MessageInterceptResult {
  final MessageInterceptAction action;
  final String? replacedText;
  final String? pluginId;

  const MessageInterceptResult._({
    required this.action,
    this.replacedText,
    this.pluginId,
  });

  /// Пропустить без изменений
  factory MessageInterceptResult.passthrough() =>
      const MessageInterceptResult._(action: MessageInterceptAction.passthrough);

  /// Заменить текст
  factory MessageInterceptResult.replace(String newText, {String? pluginId}) =>
      MessageInterceptResult._(
        action: MessageInterceptAction.replace,
        replacedText: newText,
        pluginId: pluginId,
      );

  /// Заблокировать
  factory MessageInterceptResult.block({String? pluginId}) =>
      MessageInterceptResult._(
        action: MessageInterceptAction.block,
        pluginId: pluginId,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Контекст перехватываемого сообщения
// ─────────────────────────────────────────────────────────────────────────────

enum MessageDirection { outgoing, incoming }

class MessageInterceptContext {
  final int chatId;
  final String text;
  final int senderId;
  final MessageDirection direction;

  /// Только для входящих: id сообщения с сервера
  final String? messageId;

  const MessageInterceptContext({
    required this.chatId,
    required this.text,
    required this.senderId,
    required this.direction,
    this.messageId,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Пункт меню чата от плагина
// ─────────────────────────────────────────────────────────────────────────────

class PluginChatMenuItem {
  /// Уникальный ID (используется как value в PopupMenuItem)
  final String id;

  /// Название пункта
  final String label;

  /// Иконка
  final IconData icon;

  /// Цвет (опционально, для деструктивных действий)
  final Color? color;

  /// ID плагина, который зарегистрировал пункт
  final String pluginId;

  /// Callback — вызывается при выборе пункта
  final Future<void> Function(int chatId, BuildContext context) onTap;

  const PluginChatMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    this.color,
    required this.pluginId,
    required this.onTap,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Тип функции-перехватчика
// ─────────────────────────────────────────────────────────────────────────────

typedef MessageInterceptor = Future<MessageInterceptResult> Function(
  MessageInterceptContext ctx,
);

// ─────────────────────────────────────────────────────────────────────────────
// Реестр хуков — синглтон
// ─────────────────────────────────────────────────────────────────────────────

class PluginChatHooks {
  static final PluginChatHooks _instance = PluginChatHooks._internal();
  factory PluginChatHooks() => _instance;
  PluginChatHooks._internal();

  // pluginId → interceptor
  final Map<String, MessageInterceptor> _outgoingInterceptors = {};
  final Map<String, MessageInterceptor> _incomingInterceptors = {};

  // pluginId → list of menu items
  final Map<String, List<PluginChatMenuItem>> _menuItems = {};

  final PluginPermissionsStore _perms = PluginPermissionsStore();
  bool _permsLoaded = false;

  // ───────────────────────────────────────────────
  // Регистрация перехватчиков
  // ───────────────────────────────────────────────

  /// Зарегистрировать перехватчик исходящих сообщений.
  /// Требует разрешение [PluginPermission.interceptOutgoingMessages].
  void registerOutgoingInterceptor(
    String pluginId,
    MessageInterceptor interceptor,
  ) {
    _outgoingInterceptors[pluginId] = interceptor;
  }

  /// Зарегистрировать перехватчик входящих сообщений.
  /// Требует разрешение [PluginPermission.interceptIncomingMessages].
  void registerIncomingInterceptor(
    String pluginId,
    MessageInterceptor interceptor,
  ) {
    _incomingInterceptors[pluginId] = interceptor;
  }

  void unregisterOutgoingInterceptor(String pluginId) {
    _outgoingInterceptors.remove(pluginId);
  }

  void unregisterIncomingInterceptor(String pluginId) {
    _incomingInterceptors.remove(pluginId);
  }

  // ───────────────────────────────────────────────
  // Регистрация пунктов меню
  // ───────────────────────────────────────────────

  /// Зарегистрировать пункт(ы) меню трёх точек чата.
  /// Требует разрешение [PluginPermission.addChatMenuItems].
  void registerChatMenuItems(
    String pluginId,
    List<PluginChatMenuItem> items,
  ) {
    _menuItems[pluginId] = items;
  }

  void unregisterChatMenuItems(String pluginId) {
    _menuItems.remove(pluginId);
  }

  /// Синхронно получить уже зарегистрированные пункты конкретного плагина.
  List<PluginChatMenuItem> getChatMenuItemsSync(String pluginId) {
    return List.unmodifiable(_menuItems[pluginId] ?? []);
  }

  // ───────────────────────────────────────────────
  // Применение перехватчиков (вызывается из ChatScreen)
  // ───────────────────────────────────────────────

  Future<void> _ensurePerms() async {
    if (!_permsLoaded) {
      await _perms.load();
      _permsLoaded = true;
    }
  }

  /// Прогнать исходящее сообщение через все перехватчики.
  /// Возвращает финальный текст или null если сообщение заблокировано.
  Future<String?> applyOutgoingInterceptors(
    MessageInterceptContext ctx,
  ) async {
    await _ensurePerms();

    String currentText = ctx.text;

    for (final entry in _outgoingInterceptors.entries) {
      final pluginId = entry.key;
      final interceptor = entry.value;

      // Проверяем разрешение
      if (!_perms.isGranted(pluginId, PluginPermission.interceptOutgoingMessages)) {
        continue;
      }

      try {
        final updatedCtx = MessageInterceptContext(
          chatId: ctx.chatId,
          text: currentText,
          senderId: ctx.senderId,
          direction: ctx.direction,
          messageId: ctx.messageId,
        );
        final result = await interceptor(updatedCtx);

        switch (result.action) {
          case MessageInterceptAction.block:
            debugPrint('[ChatHooks] Исходящее сообщение заблокировано плагином $pluginId');
            return null;
          case MessageInterceptAction.replace:
            if (result.replacedText != null) {
              debugPrint('[ChatHooks] Исходящее сообщение изменено плагином $pluginId');
              currentText = result.replacedText!;
            }
            break;
          case MessageInterceptAction.passthrough:
            break;
        }
      } catch (e) {
        debugPrint('[ChatHooks] Ошибка перехватчика исходящих ($pluginId): $e');
      }
    }

    return currentText;
  }

  /// Прогнать входящее сообщение через все перехватчики.
  /// Возвращает финальный текст или null если сообщение заблокировано.
  Future<String?> applyIncomingInterceptors(
    MessageInterceptContext ctx,
  ) async {
    await _ensurePerms();

    String currentText = ctx.text;

    for (final entry in _incomingInterceptors.entries) {
      final pluginId = entry.key;
      final interceptor = entry.value;

      if (!_perms.isGranted(pluginId, PluginPermission.interceptIncomingMessages)) {
        continue;
      }

      try {
        final updatedCtx = MessageInterceptContext(
          chatId: ctx.chatId,
          text: currentText,
          senderId: ctx.senderId,
          direction: ctx.direction,
          messageId: ctx.messageId,
        );
        final result = await interceptor(updatedCtx);

        switch (result.action) {
          case MessageInterceptAction.block:
            debugPrint('[ChatHooks] Входящее сообщение заблокировано плагином $pluginId');
            return null;
          case MessageInterceptAction.replace:
            if (result.replacedText != null) {
              debugPrint('[ChatHooks] Входящее сообщение изменено плагином $pluginId');
              currentText = result.replacedText!;
            }
            break;
          case MessageInterceptAction.passthrough:
            break;
        }
      } catch (e) {
        debugPrint('[ChatHooks] Ошибка перехватчика входящих ($pluginId): $e');
      }
    }

    return currentText;
  }

  // ───────────────────────────────────────────────
  // Получение пунктов меню (вызывается из ChatScreen)
  // ───────────────────────────────────────────────

  /// Получить все пункты меню от разрешённых плагинов.
  Future<List<PluginChatMenuItem>> getChatMenuItems() async {
    await _ensurePerms();

    final result = <PluginChatMenuItem>[];

    for (final entry in _menuItems.entries) {
      final pluginId = entry.key;
      final items = entry.value;

      if (!_perms.isGranted(pluginId, PluginPermission.addChatMenuItems)) {
        continue;
      }

      // Проверяем, что плагин включён
      final service = PluginService();
      final plugin = service.plugins
          .where((p) => p.id == pluginId && p.isEnabled)
          .firstOrNull;
      if (plugin == null) continue;

      result.addAll(items);
    }

    return result;
  }

  // ───────────────────────────────────────────────
  // Очистка при удалении плагина
  // ───────────────────────────────────────────────

  void removePlugin(String pluginId) {
    _outgoingInterceptors.remove(pluginId);
    _incomingInterceptors.remove(pluginId);
    _menuItems.remove(pluginId);
  }
}
