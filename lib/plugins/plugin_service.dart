import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'plugin_model.dart';
import 'plugin_permissions.dart';

class PluginService {
  static final PluginService _instance = PluginService._internal();
  factory PluginService() => _instance;
  PluginService._internal();

  final List<KometPlugin> _plugins = [];
  final Map<String, dynamic> _overriddenConstants = {};
  final Map<String, dynamic> _pluginValues = {};

  bool _initialized = false;

  List<KometPlugin> get plugins => List.unmodifiable(_plugins);
  List<KometPlugin> get enabledPlugins =>
      _plugins.where((p) => p.isEnabled).toList();

  // ─────────────────────────────────────────────
  // Инициализация: загружаем все установленные плагины
  // ─────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    // Сохраняем список ID плагинов и их директорий
    final pluginDirs = prefs.getStringList('installed_plugin_dirs') ?? [];

    for (final dir in pluginDirs) {
      try {
        final plugin = await _loadPluginFromDir(dir);
        if (plugin != null) {
          _plugins.add(plugin);
          if (plugin.isEnabled) {
            _applyPluginConstants(plugin);
          }
        }
      } catch (e) {
        debugPrint('Ошибка загрузки плагина из $dir: $e');
      }
    }

    final savedValues = prefs.getString('plugin_values');
    if (savedValues != null) {
      try {
        _pluginValues.addAll(jsonDecode(savedValues));
      } catch (_) {}
    }

    // Восстанавливаем состояния isEnabled
    final enabledMap = prefs.getString('plugin_enabled_map');
    if (enabledMap != null) {
      final map = jsonDecode(enabledMap) as Map<String, dynamic>;
      for (final plugin in _plugins) {
        if (map.containsKey(plugin.id)) {
          plugin.isEnabled = map[plugin.id] as bool;
        }
      }
    }

    _initialized = true;
  }

  // ─────────────────────────────────────────────
  // Загрузка из уже распакованной директории
  // ─────────────────────────────────────────────
  Future<KometPlugin?> _loadPluginFromDir(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return null;

    final manifestFile = File(p.join(dirPath, 'manifest.json'));
    if (!await manifestFile.exists()) return null;

    final manifestContent = await manifestFile.readAsString();
    final manifest = jsonDecode(manifestContent) as Map<String, dynamic>;

    // Ищем иконку (любое изображение с именем 'icon')
    String? iconPath;
    for (final ext in ['png', 'jpg', 'jpeg', 'webp', 'gif']) {
      final iconFile = File(p.join(dirPath, 'icon.$ext'));
      if (await iconFile.exists()) {
        iconPath = iconFile.path;
        break;
      }
    }

    // Ищем script.js
    String? scriptPath;
    final scriptFile = File(p.join(dirPath, 'script.js'));
    if (await scriptFile.exists()) {
      scriptPath = scriptFile.path;
    }

    return KometPlugin.fromManifest(
      manifest,
      dirPath,
      iconPath: iconPath,
      scriptPath: scriptPath,
    );
  }

  // ─────────────────────────────────────────────
  // Установка .kometplugin (ZIP-архив)
  // ─────────────────────────────────────────────
  Future<KometPluginInstallResult> installFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return KometPluginInstallResult.error('Файл не найден');
      }

      // Распаковываем архив
      final bytes = await file.readAsBytes();
      Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        return KometPluginInstallResult.error(
          'Файл повреждён или не является ZIP-архивом',
        );
      }

      // Находим manifest.json
      final manifestEntry = archive.files.firstWhere(
        (f) => f.name == 'manifest.json' || f.name.endsWith('/manifest.json'),
        orElse: () => throw Exception('manifest.json не найден в архиве'),
      );

      final manifestContent = utf8.decode(manifestEntry.content as List<int>);
      Map<String, dynamic> manifest;
      try {
        manifest = jsonDecode(manifestContent) as Map<String, dynamic>;
      } catch (e) {
        return KometPluginInstallResult.error(
          'manifest.json содержит ошибки: $e',
        );
      }

      final pluginId = manifest['id'] as String? ?? 
          'plugin_${DateTime.now().millisecondsSinceEpoch}';

      // Директория для распаковки
      final docsDir = await getApplicationDocumentsDirectory();
      final pluginDir = Directory(p.join(docsDir.path, 'plugins', pluginId));
      
      // Удаляем старую версию если есть
      if (await pluginDir.exists()) {
        await pluginDir.delete(recursive: true);
      }
      await pluginDir.create(recursive: true);

      // Распаковываем все файлы
      // Определяем общий префикс (если архив вложен в подпапку)
      String prefix = '';
      if (manifestEntry.name.contains('/')) {
        prefix = manifestEntry.name.substring(
          0, manifestEntry.name.lastIndexOf('/') + 1,
        );
      }

      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        
        // Убираем префикс
        String entryName = entry.name;
        if (prefix.isNotEmpty && entryName.startsWith(prefix)) {
          entryName = entryName.substring(prefix.length);
        }
        if (entryName.isEmpty) continue;

        final outFile = File(p.join(pluginDir.path, entryName));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
      }

      // Загружаем плагин из директории
      final plugin = await _loadPluginFromDir(pluginDir.path);
      if (plugin == null) {
        await pluginDir.delete(recursive: true);
        return KometPluginInstallResult.error(
          'Не удалось загрузить плагин после распаковки',
        );
      }

      // Если плагин уже установлен — заменяем
      final existingIndex = _plugins.indexWhere((p) => p.id == plugin.id);
      if (existingIndex >= 0) {
        _removePluginConstants(_plugins[existingIndex]);
        _plugins[existingIndex] = plugin;
      } else {
        _plugins.add(plugin);
      }

      if (plugin.isEnabled) {
        _applyPluginConstants(plugin);
      }

      // Инициализируем разрешения для нового плагина
      final permStore = PluginPermissionsStore();
      await permStore.load();
      await permStore.initPluginPermissions(
        plugin.id,
        plugin.requestedPermissions,
      );

      await _saveState();

      return KometPluginInstallResult.success(plugin);
    } catch (e) {
      return KometPluginInstallResult.error('Ошибка установки: $e');
    }
  }

  // ─────────────────────────────────────────────
  // Удаление плагина
  // ─────────────────────────────────────────────
  Future<void> uninstallPlugin(String pluginId) async {
    final plugin = _plugins.firstWhere(
      (p) => p.id == pluginId,
      orElse: () => throw Exception('Plugin not found'),
    );
    
    _removePluginConstants(plugin);
    _plugins.removeWhere((p) => p.id == pluginId);

    // Удаляем директорию плагина
    try {
      final dir = Directory(plugin.pluginDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Ошибка удаления директории плагина: $e');
    }

    // Удаляем разрешения плагина
    final permStore = PluginPermissionsStore();
    await permStore.load();
    await permStore.removePlugin(pluginId);

    await _saveState();
  }

  // ─────────────────────────────────────────────
  // Включение / выключение
  // ─────────────────────────────────────────────
  Future<void> setPluginEnabled(String pluginId, bool enabled) async {
    final plugin = _plugins.firstWhere((p) => p.id == pluginId);
    plugin.isEnabled = enabled;

    if (enabled) {
      _applyPluginConstants(plugin);
    } else {
      _removePluginConstants(plugin);
    }

    await _saveState();
  }

  // ─────────────────────────────────────────────
  // Константы
  // ─────────────────────────────────────────────
  void _applyPluginConstants(KometPlugin plugin) {
    for (final entry in plugin.overrideConstants.entries) {
      _overriddenConstants[entry.key] = entry.value;
    }
  }

  void _removePluginConstants(KometPlugin plugin) {
    for (final key in plugin.overrideConstants.keys) {
      _overriddenConstants.remove(key);
    }
  }

  T? getConstant<T>(String key, T defaultValue) {
    if (_overriddenConstants.containsKey(key)) {
      return _overriddenConstants[key] as T;
    }
    return defaultValue;
  }

  // ─────────────────────────────────────────────
  // Значения плагинов
  // ─────────────────────────────────────────────
  dynamic getPluginValue(String key, dynamic defaultValue) {
    return _pluginValues[key] ?? defaultValue;
  }

  Future<void> setPluginValue(String key, dynamic value) async {
    _pluginValues[key] = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plugin_values', jsonEncode(_pluginValues));
  }

  // ─────────────────────────────────────────────
  // Сохранение состояния
  // ─────────────────────────────────────────────
  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    
    final dirs = _plugins.map((p) => p.pluginDir).toList();
    await prefs.setStringList('installed_plugin_dirs', dirs);

    final enabledMap = {for (final p in _plugins) p.id: p.isEnabled};
    await prefs.setString('plugin_enabled_map', jsonEncode(enabledMap));
  }

  // ─────────────────────────────────────────────
  // Геттеры для настроек
  // ─────────────────────────────────────────────
  List<PluginSection> getAllPluginSections() {
    final sections = <PluginSection>[];
    for (final plugin in enabledPlugins) {
      sections.addAll(plugin.settingsSections);
    }
    return sections;
  }

  List<PluginSubsection> getSubsectionsFor(String parentSection) {
    final subsections = <PluginSubsection>[];
    for (final plugin in enabledPlugins) {
      subsections.addAll(
        plugin.settingsSubsections.where(
          (s) => s.parentSection == parentSection,
        ),
      );
    }
    return subsections;
  }

  PluginScreen? getReplacementScreen(String screenId) {
    for (final plugin in enabledPlugins) {
      if (plugin.replaceScreens.containsKey(screenId)) {
        return plugin.replaceScreens[screenId];
      }
    }
    return null;
  }

  bool isScreenReplaced(String screenId) {
    if (screenId == 'PluginsScreen') return false;
    return enabledPlugins.any((p) => p.replaceScreens.containsKey(screenId));
  }

  // ─────────────────────────────────────────────
  // Выполнение действий
  // ─────────────────────────────────────────────
  Future<void> executeAction(PluginAction action, BuildContext context) async {
    switch (action.type) {
      case PluginActionType.setValue:
        await setPluginValue(action.target, action.value);
        break;
      case PluginActionType.callAction:
        await _executeBuiltinAction(action.target, context);
        break;
      case PluginActionType.openUrl:
        final uri = Uri.parse(action.target);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
      case PluginActionType.navigate:
        break;
    }
  }

  Future<void> _executeBuiltinAction(String actionId, BuildContext context) async {
    switch (actionId) {
      case 'clear_cache':
        break;
      case 'reconnect':
        break;
      case 'show_snackbar':
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Действие выполнено!')),
          );
        }
        break;
    }
  }

  static const Map<String, String> availableActions = {
    'clear_cache': 'Очистить кэш',
    'reconnect': 'Переподключиться',
    'show_snackbar': 'Показать уведомление',
  };
}

// ─────────────────────────────────────────────
// Результат установки
// ─────────────────────────────────────────────
class KometPluginInstallResult {
  final bool success;
  final KometPlugin? plugin;
  final String? errorMessage;

  KometPluginInstallResult._({
    required this.success,
    this.plugin,
    this.errorMessage,
  });

  factory KometPluginInstallResult.success(KometPlugin plugin) =>
      KometPluginInstallResult._(success: true, plugin: plugin);

  factory KometPluginInstallResult.error(String message) =>
      KometPluginInstallResult._(success: false, errorMessage: message);
}
