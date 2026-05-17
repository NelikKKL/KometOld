import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gwid/plugins/plugin_model.dart';
import 'package:gwid/plugins/plugin_service.dart';
import 'package:gwid/plugins/plugin_chat_hooks.dart';
import 'package:gwid/screens/settings/plugin_permissions_screen.dart';

class PluginsScreen extends StatefulWidget {
  const PluginsScreen({super.key});

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

class _PluginsScreenState extends State<PluginsScreen> {
  final PluginService _pluginService = PluginService();
  bool _isLoading = false;
  String? _loadingMessage;

  @override
  void initState() {
    super.initState();
    _initPlugins();
  }

  Future<void> _initPlugins() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Загрузка плагинов...';
    });
    await _pluginService.initialize();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plugins = _pluginService.plugins;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Плагины',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 22),
              onPressed: _isLoading ? null : _pickPluginFile,
              tooltip: 'Установить плагин (.kometplugin)',
            ),
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState(theme)
          : plugins.isEmpty
              ? _buildEmptyState(theme)
              : _buildPluginList(plugins, theme),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          if (_loadingMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              _loadingMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.extension_rounded,
                size: 48,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Нет установленных плагинов',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите + чтобы выбрать\nфайл плагина .kometplugin',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _pickPluginFile,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Выбрать .kometplugin'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPluginList(List<KometPlugin> plugins, ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: plugins.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final plugin = plugins[index];
        return _PluginListTile(
          plugin: plugin,
          onToggle: (enabled) => _togglePlugin(plugin.id, enabled),
          onDelete: () => _deletePlugin(plugin.id),
          onTap: () => _showPluginDetails(plugin),
          onShowPermissions: () => _showPermissions(plugin),
        );
      },
    );
  }

  Future<void> _pickPluginFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['kometplugin'],
        withData: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.first.path;
        if (filePath != null) {
          await _installPlugin(filePath);
        }
      }
    } catch (e) {
      _showError('Ошибка выбора файла: $e');
    }
  }

  Future<void> _installPlugin(String filePath) async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Установка плагина...';
    });

    try {
      final result = await _pluginService.installFromFile(filePath);

      if (!mounted) return;

      if (!result.success) {
        _showError(result.errorMessage ?? 'Неизвестная ошибка');
        return;
      }

      final plugin = result.plugin!;

      // Показываем диалог подтверждения установки
      final confirmed = await _showInstallDialog(plugin);
      if (confirmed != true) {
        // Пользователь отменил — откатываем
        await _pluginService.uninstallPlugin(plugin.id);
        return;
      }

      setState(() {});
      _showSuccessSnack('Плагин "${plugin.name}" установлен');
    } catch (e) {
      _showError('Ошибка установки: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = null;
        });
      }
    }
  }

  Future<bool?> _showInstallDialog(KometPlugin plugin) {
    return showDialog<bool>(
      context: context,
      builder: (context) => _InstallDialog(plugin: plugin),
    );
  }

  Future<void> _togglePlugin(String pluginId, bool enabled) async {
    await _pluginService.setPluginEnabled(pluginId, enabled);
    setState(() {});
  }

  Future<void> _deletePlugin(String pluginId) async {
    final plugin = _pluginService.plugins.firstWhere((p) => p.id == pluginId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeletePluginDialog(plugin: plugin),
    );

    if (confirmed == true) {
      // Очищаем хуки чата перед удалением
      PluginChatHooks().removePlugin(pluginId);
      await _pluginService.uninstallPlugin(pluginId);
      setState(() {});
      _showSuccessSnack('Плагин "${plugin.name}" удалён');
    }
  }

  void _showPluginDetails(KometPlugin plugin) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PluginDetailsSheet(plugin: plugin),
    );
  }

  void _showPermissions(KometPlugin plugin) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PluginPermissionsScreen(plugin: plugin),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Плитка плагина (как пункт настроек)
// Вид: | иконка  название |
//      |     описание     |
// ─────────────────────────────────────────────────────────────
class _PluginListTile extends StatelessWidget {
  final KometPlugin plugin;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final VoidCallback onShowPermissions;

  const _PluginListTile({
    required this.plugin,
    required this.onToggle,
    required this.onDelete,
    required this.onTap,
    required this.onShowPermissions,
  });

  void _showContextMenu(BuildContext context) {
    final theme = Theme.of(context);
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset offset = box.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + 40,
        offset.dx + box.size.width,
        offset.dy + box.size.height,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 4,
      items: [
        PopupMenuItem<String>(
          value: 'permissions',
          child: Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Разрешения',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 12),
              Text(
                'Удалить',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') onDelete();
      if (value == 'permissions') onShowPermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showContextMenu(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Иконка плагина
              _PluginIcon(iconPath: plugin.iconPath, size: 52),
              const SizedBox(width: 14),
              // Название + описание
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            plugin.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: plugin.isEnabled
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.4),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'v${plugin.version}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    if (plugin.description != null &&
                        plugin.description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        plugin.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else ...[
                      const SizedBox(height: 2),
                      Text(
                        plugin.author != null
                            ? 'Автор: ${plugin.author}'
                            : 'Нет описания',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.4),
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Переключатель
              Switch(
                value: plugin.isEnabled,
                onChanged: onToggle,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Иконка плагина
// ─────────────────────────────────────────────────────────────
class _PluginIcon extends StatelessWidget {
  final String? iconPath;
  final double size;

  const _PluginIcon({this.iconPath, required this.size});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(size * 0.22);

    if (iconPath != null) {
      final file = File(iconPath!);
      return ClipRRect(
        borderRadius: radius,
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(theme, radius),
        ),
      );
    }
    return _fallback(theme, radius);
  }

  Widget _fallback(ThemeData theme, BorderRadius radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: radius,
      ),
      child: Icon(
        Icons.extension_rounded,
        size: size * 0.5,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Диалог подтверждения установки
// ─────────────────────────────────────────────────────────────
class _InstallDialog extends StatelessWidget {
  final KometPlugin plugin;

  const _InstallDialog({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = plugin.getSummary();

    return AlertDialog(
      title: Text('Установить плагин?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Шапка с иконкой и именем
            Row(
              children: [
                _PluginIcon(iconPath: plugin.iconPath, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plugin.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        [
                          'v${plugin.version}',
                          if (plugin.author != null) plugin.author!,
                        ].join(' • '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (plugin.description != null &&
                plugin.description!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(plugin.description!, style: theme.textTheme.bodyMedium),
            ],
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Этот плагин:',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 6),
              ...summary.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(s, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Установить'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bottom sheet с деталями плагина
// ─────────────────────────────────────────────────────────────
class _PluginDetailsSheet extends StatelessWidget {
  final KometPlugin plugin;

  const _PluginDetailsSheet({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = plugin.getSummary();

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            // Ручка
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Шапка
            Row(
              children: [
                _PluginIcon(iconPath: plugin.iconPath, size: 68),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plugin.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Версия ${plugin.version}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                      if (plugin.author != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 14,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              plugin.author!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (plugin.description != null &&
                plugin.description!.isNotEmpty) ...[
              Text(
                plugin.description!,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
            ],
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Возможности',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            if (summary.isEmpty)
              Text(
                'Плагин не добавляет дополнительных функций',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              ...summary.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s)),
                    ],
                  ),
                ),
              ),
            if (plugin.scriptPath != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.code_rounded,
                      size: 18,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Содержит JavaScript (script.js)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (plugin.overrideConstants.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                'Переопределяемые константы',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              ...plugin.overrideConstants.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.key,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      Text(
                        '${e.value}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Диалог удаления плагина с обратным отсчётом 3 секунды
// Вызывается через долгое нажатие на плагин
// ─────────────────────────────────────────────────────────────
class _DeletePluginDialog extends StatefulWidget {
  final KometPlugin plugin;

  const _DeletePluginDialog({required this.plugin});

  @override
  State<_DeletePluginDialog> createState() => _DeletePluginDialogState();
}

class _DeletePluginDialogState extends State<_DeletePluginDialog> {
  int _countdown = 3;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdown--);
      return _countdown > 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDelete = _countdown <= 0;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Удалить плагин?'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PluginIcon(iconPath: widget.plugin.iconPath, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.plugin.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Плагин будет удалён без возможности восстановления.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: canDelete ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            disabledBackgroundColor:
                theme.colorScheme.error.withValues(alpha: 0.4),
            disabledForegroundColor: theme.colorScheme.onError.withValues(alpha: 0.7),
          ),
          child: Text(
            _countdown > 0 ? 'Удалить ($_countdown)' : 'Удалить',
          ),
        ),
      ],
    );
  }
}
