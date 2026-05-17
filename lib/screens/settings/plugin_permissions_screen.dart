import 'package:flutter/material.dart';
import 'package:gwid/plugins/plugin_model.dart';
import 'package:gwid/plugins/plugin_permissions.dart';

/// Экран управления разрешениями конкретного плагина.
/// Открывается из контекстного меню в списке плагинов.
class PluginPermissionsScreen extends StatefulWidget {
  final KometPlugin plugin;

  const PluginPermissionsScreen({super.key, required this.plugin});

  @override
  State<PluginPermissionsScreen> createState() =>
      _PluginPermissionsScreenState();
}

class _PluginPermissionsScreenState extends State<PluginPermissionsScreen> {
  final PluginPermissionsStore _store = PluginPermissionsStore();
  Map<PluginPermission, bool> _permissions = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _store.load();
    setState(() {
      _permissions = _store.getAll(widget.plugin.id);
      _loading = false;
    });
  }

  Future<void> _toggle(PluginPermission permission, bool value) async {
    await _store.setPermission(widget.plugin.id, permission, value);
    setState(() {
      _permissions[permission] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Группируем разрешения
    final sensitivePerms = PluginPermission.values
        .where((p) => p.isSensitive)
        .toList();
    final normalPerms = PluginPermission.values
        .where((p) => !p.isSensitive)
        .toList();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Разрешения',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              widget.plugin.name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // Плашка с описанием
                _InfoCard(theme: theme),
                const SizedBox(height: 20),

                // Чувствительные разрешения
                _SectionLabel(
                  label: 'Доступ к данным',
                  icon: Icons.privacy_tip_outlined,
                  color: theme.colorScheme.error,
                  theme: theme,
                ),
                const SizedBox(height: 8),
                ...sensitivePerms.map(
                  (p) => _PermissionTile(
                    permission: p,
                    granted: _permissions[p] ?? false,
                    onChanged: (v) => _toggle(p, v),
                    theme: theme,
                  ),
                ),
                const SizedBox(height: 20),

                // Обычные разрешения
                _SectionLabel(
                  label: 'Функции приложения',
                  icon: Icons.extension_outlined,
                  color: theme.colorScheme.primary,
                  theme: theme,
                ),
                const SizedBox(height: 8),
                ...normalPerms.map(
                  (p) => _PermissionTile(
                    permission: p,
                    granted: _permissions[p] ?? false,
                    onChanged: (v) => _toggle(p, v),
                    theme: theme,
                  ),
                ),

                const SizedBox(height: 24),
                // Кнопка — отозвать все
                OutlinedButton.icon(
                  onPressed: _revokeAll,
                  icon: Icon(
                    Icons.block_rounded,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    'Отозвать все разрешения',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: theme.colorScheme.error.withValues(alpha: 0.5),
                    ),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _revokeAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отозвать все разрешения?'),
        content: Text(
          'Все разрешения плагина «${widget.plugin.name}» будут отозваны. '
          'Плагин может перестать работать.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Отозвать'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final p in PluginPermission.values) {
      await _store.setPermission(widget.plugin.id, p, false);
    }
    setState(() {
      _permissions = {for (final p in PluginPermission.values) p: false};
    });
  }
}

class _InfoCard extends StatelessWidget {
  final ThemeData theme;
  const _InfoCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Отключение разрешений может нарушить работу плагина. '
              'Изменения вступают в силу немедленно.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final ThemeData theme;

  const _SectionLabel({
    required this.label,
    required this.icon,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final PluginPermission permission;
  final bool granted;
  final ValueChanged<bool> onChanged;
  final ThemeData theme;

  const _PermissionTile({
    required this.permission,
    required this.granted,
    required this.onChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: granted
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: granted
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
                width: 1,
              )
            : null,
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        secondary: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: granted
                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                : theme.colorScheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _iconData(permission.iconName),
            size: 18,
            color: granted
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
        title: Text(
          permission.displayName,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: granted
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        subtitle: Text(
          permission.description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
        value: granted,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  IconData _iconData(String name) {
    // Flutter не позволяет получить IconData по строке напрямую, используем switch
    switch (name) {
      case 'chat_bubble_outline':
        return Icons.chat_bubble_outline_rounded;
      case 'message':
        return Icons.message_rounded;
      case 'people_outline':
        return Icons.people_outline_rounded;
      case 'person_outline':
        return Icons.person_outline_rounded;
      case 'notifications_active':
        return Icons.notifications_active_rounded;
      case 'sync':
        return Icons.sync_rounded;
      case 'tune':
        return Icons.tune_rounded;
      case 'layers':
        return Icons.layers_rounded;
      case 'settings':
        return Icons.settings_rounded;
      case 'edit':
        return Icons.edit_rounded;
      case 'move_to_inbox':
        return Icons.move_to_inbox_rounded;
      case 'more_vert':
        return Icons.more_vert_rounded;
      default:
        return Icons.extension_rounded;
    }
  }
}
