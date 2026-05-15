import 'package:flutter/material.dart';
import 'package:gwid/plugins/plugin_model.dart';
import 'package:gwid/plugins/plugin_service.dart';
import 'package:gwid/plugins/plugin_ui_builder.dart';

/// Экран окна плагина — может открываться как fullscreen или bottomSheet
class PluginWindowScreen extends StatelessWidget {
  final PluginWindowDef window;
  final String? pluginName;

  const PluginWindowScreen({
    super.key,
    required this.window,
    this.pluginName,
  });

  /// Открыть окно плагина нужным способом
  static void open(
    BuildContext context,
    PluginWindowDef window, {
    String? pluginName,
  }) {
    if (window.fullScreen) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PluginWindowScreen(
            window: window,
            pluginName: pluginName,
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PluginWindowBottomSheet(
          window: window,
          pluginName: pluginName,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final builder = PluginUIBuilder();
    return Scaffold(
      appBar: AppBar(
        title: Text(window.title),
        subtitle: pluginName != null
            ? Text(
                pluginName!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              )
            : null,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: window.widgets.length,
        itemBuilder: (context, index) {
          return builder.buildWidget(window.widgets[index], context);
        },
      ),
    );
  }
}

class _PluginWindowBottomSheet extends StatelessWidget {
  final PluginWindowDef window;
  final String? pluginName;

  const _PluginWindowBottomSheet({required this.window, this.pluginName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final builder = PluginUIBuilder();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Ручка + заголовок
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        Icons.extension_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              window.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (pluginName != null)
                              Text(
                                pluginName!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                ],
              ),
            ),
            // Контент
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
                itemCount: window.widgets.length,
                itemBuilder: (context, index) {
                  return builder.buildWidget(window.widgets[index], context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
