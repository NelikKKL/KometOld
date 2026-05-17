import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Все доступные разрешения для плагинов
enum PluginPermission {
  /// Читать список чатов (id, название, тип, время последнего сообщения)
  readChats,

  /// Читать сообщения в чатах
  readMessages,

  /// Читать список контактов
  readContacts,

  /// Читать профиль текущего пользователя
  readSelfProfile,

  /// Получать события новых сообщений в реальном времени
  receiveMessageEvents,

  /// Получать события изменения статуса чата
  receiveChatEvents,

  /// Изменять значения констант приложения
  overrideConstants,

  /// Заменять экраны приложения
  replaceScreens,

  /// Добавлять разделы в настройки
  addSettingsSections,

  /// Перехватывать и редактировать исходящие сообщения перед отправкой
  interceptOutgoingMessages,

  /// Перехватывать и редактировать входящие сообщения перед отображением
  interceptIncomingMessages,

  /// Добавлять пункты в меню трёх точек чата
  addChatMenuItems,
}

extension PluginPermissionExt on PluginPermission {
  String get displayName {
    switch (this) {
      case PluginPermission.readChats:
        return 'Читать чаты';
      case PluginPermission.readMessages:
        return 'Читать сообщения';
      case PluginPermission.readContacts:
        return 'Читать контакты';
      case PluginPermission.readSelfProfile:
        return 'Читать свой профиль';
      case PluginPermission.receiveMessageEvents:
        return 'События новых сообщений';
      case PluginPermission.receiveChatEvents:
        return 'События изменения чатов';
      case PluginPermission.overrideConstants:
        return 'Изменять константы';
      case PluginPermission.replaceScreens:
        return 'Заменять экраны';
      case PluginPermission.addSettingsSections:
        return 'Добавлять в настройки';
      case PluginPermission.interceptOutgoingMessages:
        return 'Перехват исходящих';
      case PluginPermission.interceptIncomingMessages:
        return 'Перехват входящих';
      case PluginPermission.addChatMenuItems:
        return 'Пункты меню чата';
    }
  }

  String get description {
    switch (this) {
      case PluginPermission.readChats:
        return 'Доступ к списку чатов: названия, типы, превью';
      case PluginPermission.readMessages:
        return 'Доступ к истории сообщений в чатах';
      case PluginPermission.readContacts:
        return 'Доступ к списку ваших контактов';
      case PluginPermission.readSelfProfile:
        return 'Доступ к информации вашего аккаунта';
      case PluginPermission.receiveMessageEvents:
        return 'Уведомления о новых сообщениях в реальном времени';
      case PluginPermission.receiveChatEvents:
        return 'Уведомления об изменениях чатов';
      case PluginPermission.overrideConstants:
        return 'Изменение внутренних параметров приложения';
      case PluginPermission.replaceScreens:
        return 'Замена стандартных экранов приложения';
      case PluginPermission.addSettingsSections:
        return 'Добавление новых разделов в настройки';
      case PluginPermission.interceptOutgoingMessages:
        return 'Читать и изменять ваши сообщения перед отправкой';
      case PluginPermission.interceptIncomingMessages:
        return 'Читать и изменять входящие сообщения перед показом';
      case PluginPermission.addChatMenuItems:
        return 'Добавлять кнопки в меню ⋮ открытого чата';
    }
  }

  /// Иконка для отображения в UI (Material icon name как строка)
  String get iconName {
    switch (this) {
      case PluginPermission.readChats:
        return 'chat_bubble_outline';
      case PluginPermission.readMessages:
        return 'message';
      case PluginPermission.readContacts:
        return 'people_outline';
      case PluginPermission.readSelfProfile:
        return 'person_outline';
      case PluginPermission.receiveMessageEvents:
        return 'notifications_active';
      case PluginPermission.receiveChatEvents:
        return 'sync';
      case PluginPermission.overrideConstants:
        return 'tune';
      case PluginPermission.replaceScreens:
        return 'layers';
      case PluginPermission.addSettingsSections:
        return 'settings';
      case PluginPermission.interceptOutgoingMessages:
        return 'edit';
      case PluginPermission.interceptIncomingMessages:
        return 'move_to_inbox';
      case PluginPermission.addChatMenuItems:
        return 'more_vert';
    }
  }

  /// Считается ли разрешение «чувствительным» (требует особого внимания)
  bool get isSensitive {
    switch (this) {
      case PluginPermission.readMessages:
      case PluginPermission.readContacts:
      case PluginPermission.readSelfProfile:
      case PluginPermission.receiveMessageEvents:
      case PluginPermission.interceptOutgoingMessages:
      case PluginPermission.interceptIncomingMessages:
        return true;
      default:
        return false;
    }
  }
}

/// Хранилище состояний разрешений для всех плагинов
class PluginPermissionsStore {
  static final PluginPermissionsStore _instance =
      PluginPermissionsStore._internal();
  factory PluginPermissionsStore() => _instance;
  PluginPermissionsStore._internal();

  static const String _prefsKey = 'plugin_permissions_v1';

  /// pluginId → Map<permissionName, isGranted>
  final Map<String, Map<String, bool>> _store = {};

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          _store[entry.key] = Map<String, bool>.from(entry.value as Map);
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_store));
  }

  /// Проверить, выдано ли разрешение
  bool isGranted(String pluginId, PluginPermission permission) {
    final pluginPerms = _store[pluginId];
    if (pluginPerms == null) return false;
    return pluginPerms[permission.name] ?? false;
  }

  /// Получить все разрешения плагина (Map<permission, isGranted>)
  Map<PluginPermission, bool> getAll(String pluginId) {
    final pluginPerms = _store[pluginId] ?? {};
    return {
      for (final p in PluginPermission.values)
        p: pluginPerms[p.name] ?? false,
    };
  }

  /// Установить разрешение
  Future<void> setPermission(
    String pluginId,
    PluginPermission permission,
    bool granted,
  ) async {
    _store.putIfAbsent(pluginId, () => {});
    _store[pluginId]![permission.name] = granted;
    await _save();
  }

  /// Выдать список разрешений из манифеста (при первой установке)
  /// Разрешения из manifest.json помечаются как запрошенные, но не выданные.
  /// Пользователь сам решает что разрешить в экране разрешений.
  Future<void> initPluginPermissions(
    String pluginId,
    List<String> requestedPermissions,
  ) async {
    _store.putIfAbsent(pluginId, () => {});
    final existing = _store[pluginId]!;
    for (final permName in requestedPermissions) {
      // Инициализируем только если ещё нет записи
      if (!existing.containsKey(permName)) {
        existing[permName] = false;
      }
    }
    await _save();
  }

  /// Удалить все разрешения плагина (при удалении)
  Future<void> removePlugin(String pluginId) async {
    _store.remove(pluginId);
    await _save();
  }
}
