import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gwid/utils/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BypassScreen extends StatefulWidget {
  final bool isModal;

  const BypassScreen({super.key, this.isModal = false});

  @override
  State<BypassScreen> createState() => _BypassScreenState();
}

class _BypassScreenState extends State<BypassScreen> {
  int _selectedTab = 0;
  bool _kometAutoCompleteEnabled = false;
  bool _specialMessagesEnabled = true;
  bool _isLoadingSettings = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _kometAutoCompleteEnabled =
          prefs.getBool('komet_auto_complete_enabled') ?? false;
      _specialMessagesEnabled =
          prefs.getBool('special_messages_enabled') ?? true;
      _isLoadingSettings = false;
    });
  }

  Future<void> _saveSpecialMessages(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('special_messages_enabled', value);
    setState(() {
      _specialMessagesEnabled = value;
    });
  }

  Future<void> _saveKometAutoComplete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('komet_auto_complete_enabled', value);
    setState(() {
      _kometAutoCompleteEnabled = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isModal) {
      final colors = Theme.of(context).colorScheme;
      return _buildModalSettings(context, colors);
    }
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Специальные возможности и фишки")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 480;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colors.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (_selectedTab != 0) {
                            setState(() => _selectedTab = 0);
                          }
                        },
                        child: _SegmentButton(
                          selected: _selectedTab == 0,
                          label: isNarrow ? 'Bypass' : 'Обходы',
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (_selectedTab != 1) {
                            setState(() => _selectedTab = 1);
                          }
                        },
                        child: _SegmentButton(
                          selected: _selectedTab == 1,
                          label: isNarrow ? 'Фишки' : 'Фишки (komet.color)',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          if (_selectedTab == 0) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        "Обход блокировки",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Эта функция позволяет отправлять сообщения заблокированным пользователям. "
                    "Включите эту опцию, если хотите обойти "
                    "стандартные ограничения мессенджера.",
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                return Card(
                  child: SwitchListTile(
                    title: const Text(
                      "Обход блокировки",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      "Разрешить отправку сообщений заблокированным пользователям",
                    ),
                    value: themeProvider.blockBypass,
                    onChanged: (value) {
                      themeProvider.setBlockBypass(value);
                    },
                    secondary: Icon(
                      themeProvider.blockBypass
                          ? Icons.psychology
                          : Icons.psychology_outlined,
                      color: themeProvider.blockBypass
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_outlined,
                        color: colors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "ВНИМНИЕ🚨🚨🚨",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Используя любую из bypass функций, вас возможно накажут",
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.outline.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.color_lens_outlined, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Фишки (цветные никнеймы, скоро)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "В будущих версиях можно будет подсвечивать отдельные буквы и слова в нике с помощью простого синтаксиса, а также добавлять визуальные эффекты к сообщениям.",
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colors.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Простой пример (цветники):",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          "komet.color_#FF0000'привет'",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              "Отображение: ",
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                            const Text(
                              "привет",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFF0000),
                              ),
                            ),
                            Text(
                              "",
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Пример (пульсирующий текст):",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          "komet.cosmetic.pulse#FF0000'пульсирующий текст'",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Отображение: текст «пульсирующий текст» в пузыре сообщения пульсирует указанным цветом (в данном случае красным).",
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Пример (переливающийся ч/б текст в сообщении):",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          "komet.cosmetic.galaxy'тестовое сообщение'",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Отображение:",
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(
                              alpha: 0.6,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const _GalaxyDemoText(
                            text: "тестовое сообщение",
                          ),
                        ),
                        const SizedBox(height: 16),
                        // ── komet.omm section ──
                        Text(
                          "3D модель (komet.omm):",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Отображает интерактивную 3D модель прямо в пузыре сообщения. Поддерживает форматы cube, sphere, pyramid, cylinder, triangle.",
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          "komet.omm'cube3\ncolor(255,100,50)\nautorate\n'",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "• cube3 / sphere3 / pyramid3 / cylinder3 / triangle3 — фигура\n"
                          "• color(R,G,B) — цвет фигуры\n"
                          "• autorate — автовращение\n"
                          "• scale(N) — масштаб\n"
                          "• rr(N) / ru(N) — начальный поворот\n"
                          "• x(N) y(N) z(N) — позиция",
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Сложный пример:",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            SelectableText(
                              "komet.color_#FFFFFF'п'",
                              style: TextStyle(fontFamily: 'monospace'),
                            ),
                            SelectableText(
                              "komet.color_#FF0000'р'",
                              style: TextStyle(fontFamily: 'monospace'),
                            ),
                            SelectableText(
                              "komet.color_#00FF00'и'",
                              style: TextStyle(fontFamily: 'monospace'),
                            ),
                            SelectableText(
                              "komet.color_#0000FF'в'",
                              style: TextStyle(fontFamily: 'monospace'),
                            ),
                            SelectableText(
                              "komet.color_#FFFF00'е'",
                              style: TextStyle(fontFamily: 'monospace'),
                            ),
                            SelectableText(
                              "komet.color_#FF00FF'т'",
                              style: TextStyle(fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "В сообщении эти куски пишутся подряд без пробелов и переносов строки — здесь они показаны столбиком для наглядности.",
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              "Отображение: ",
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                            const Text(
                              "п",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFFFFFF),
                              ),
                            ),
                            const Text(
                              "р",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFF0000),
                              ),
                            ),
                            const Text(
                              "и",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF00FF00),
                              ),
                            ),
                            const Text(
                              "в",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0000FF),
                              ),
                            ),
                            const Text(
                              "е",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFFFF00),
                              ),
                            ),
                            const Text(
                              "т",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFF00FF),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!_isLoadingSettings) ...[
                    Consumer<ThemeProvider>(
                      builder: (context, themeProvider, child) {
                        return Card(
                          child: SwitchListTile(
                            title: const Text(
                              'Авто-дополнение уникальных сообщений',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Показывать панель выбора цвета при вводе komet.color#',
                            ),
                            value: _kometAutoCompleteEnabled,
                            onChanged: (value) {
                              _saveKometAutoComplete(value);
                            },
                            secondary: Icon(
                              _kometAutoCompleteEnabled
                                  ? Icons.auto_awesome
                                  : Icons.auto_awesome_outlined,
                              color: _kometAutoCompleteEnabled
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Consumer<ThemeProvider>(
                      builder: (context, themeProvider, child) {
                        return Card(
                          child: SwitchListTile(
                            title: const Text(
                              'Включить список особых сообщений',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Показывать кнопку для быстрой вставки шаблонов особых сообщений',
                            ),
                            value: _specialMessagesEnabled,
                            onChanged: (value) {
                              _saveSpecialMessages(value);
                            },
                            secondary: Icon(
                              _specialMessagesEnabled
                                  ? Icons.auto_fix_high
                                  : Icons.auto_fix_high_outlined,
                              color: _specialMessagesEnabled
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModalSettings(BuildContext context, ColorScheme colors) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black.withValues(alpha: 0.3),
            ),
          ),

          Center(
            child: Container(
              width: 400,
              height: 600,
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                          tooltip: 'Назад',
                        ),
                        const Expanded(
                          child: Text(
                            "Специальные возможности и фишки",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          tooltip: 'Закрыть',
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer.withValues(
                              alpha: 0.3,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colors.outline.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: colors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Информация",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colors.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Эта функция предназначена для обхода ограничений и блокировок. Используйте с осторожностью и только в законных целях.",
                                style: TextStyle(
                                  color: colors.onSurface.withValues(
                                    alpha: 0.8,
                                  ),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Consumer<ThemeProvider>(
                          builder: (context, themeProvider, child) {
                            return Card(
                              child: SwitchListTile(
                                title: const Text(
                                  "Обход блокировки",
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: const Text(
                                  "Разрешить отправку сообщений заблокированным пользователям",
                                ),
                                value: themeProvider.blockBypass,
                                onChanged: (value) {
                                  themeProvider.setBlockBypass(value);
                                },
                                secondary: Icon(
                                  themeProvider.blockBypass
                                      ? Icons.psychology
                                      : Icons.psychology_outlined,
                                  color: themeProvider.blockBypass
                                      ? colors.primary
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GalaxyDemoText extends StatefulWidget {
  final String text;

  const _GalaxyDemoText({required this.text});

  @override
  State<_GalaxyDemoText> createState() => _GalaxyDemoTextState();
}

class _GalaxyDemoTextState extends State<_GalaxyDemoText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final color = Color.lerp(Colors.black, Colors.white, t)!;

        return ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, Color.lerp(Colors.white, Colors.black, t)!],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: Text(
            widget.text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final bool selected;
  final String label;

  const _SegmentButton({required this.selected, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? colors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? colors.onPrimary : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
