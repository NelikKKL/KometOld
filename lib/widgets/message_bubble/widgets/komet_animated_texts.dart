import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class GalaxyAnimatedText extends StatefulWidget {
  final String text;

  const GalaxyAnimatedText({super.key, required this.text});

  @override
  State<GalaxyAnimatedText> createState() => _GalaxyAnimatedTextState();
}

class _GalaxyAnimatedTextState extends State<GalaxyAnimatedText>
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

class PulseAnimatedText extends StatefulWidget {
  final String text;

  const PulseAnimatedText({super.key, required this.text});

  @override
  State<PulseAnimatedText> createState() => _PulseAnimatedTextState();
}

class _PulseAnimatedTextState extends State<PulseAnimatedText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Color? _pulseColor;

  @override
  void initState() {
    super.initState();
    _parseColor();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  void _parseColor() {
    final text = widget.text;
    const prefix = "komet.cosmetic.pulse#";
    if (!text.startsWith(prefix)) {
      _pulseColor = Colors.red;
      return;
    }

    final afterHash = text.substring(prefix.length);
    final quoteIndex = afterHash.indexOf("'");
    if (quoteIndex == -1) {
      _pulseColor = Colors.red;
      return;
    }

    final hexStr = afterHash.substring(0, quoteIndex).trim();
    _pulseColor = _parseHexColor(hexStr);
  }

  Color _parseHexColor(String hex) {
    String hexClean = hex.trim();
    if (hexClean.startsWith('#')) {
      hexClean = hexClean.substring(1);
    }

    if (hexClean.isEmpty) {
      return Colors.red;
    }

    if (hexClean.length == 3) {
      hexClean =
          '${hexClean[0]}${hexClean[0]}${hexClean[1]}${hexClean[1]}${hexClean[2]}${hexClean[2]}';
    } else if (hexClean.length == 4) {
      hexClean =
          '${hexClean[0]}${hexClean[0]}${hexClean[1]}${hexClean[1]}${hexClean[2]}${hexClean[2]}${hexClean[3]}${hexClean[3]}';
    } else if (hexClean.length == 5) {
      hexClean = '0$hexClean';
    } else if (hexClean.length < 6) {
      hexClean = hexClean.padRight(6, '0');
    } else if (hexClean.length > 6) {
      hexClean = hexClean.substring(0, 6);
    }

    try {
      return Color(int.parse('FF$hexClean', radix: 16));
    } catch (e) {
      return Colors.red;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    const prefix = "komet.cosmetic.pulse#";
    if (!text.startsWith(prefix) || !text.endsWith("'")) {
      return Text(text);
    }

    final afterHash = text.substring(prefix.length);
    final quoteIndex = afterHash.indexOf("'");
    if (quoteIndex == -1 || quoteIndex + 1 >= afterHash.length) {
      return Text(text);
    }

    final textStart = quoteIndex + 1;
    final secondQuote = afterHash.indexOf("'", textStart);
    if (secondQuote == -1) {
      return Text(text);
    }

    final messageText = afterHash.substring(textStart, secondQuote);
    final baseColor = _pulseColor ?? Colors.red;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final opacity = 0.5 + (t * 0.5);
        final color = baseColor.withValues(alpha: opacity);

        return Text(
          messageText,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OmmWidget — рендерит 3D-модель komet.omm прямо в пузыре сообщения.
// Синтаксис: komet.omm(цвет)' OMM-код '
//   где (цвет) — необязательный hex-цвет фона (можно опустить скобки).
//
// Примеры:
//   komet.omm' cube3 color(255,100,50) '
//   komet.omm(#1a1a2e)' cube3 scale(1.5) animation(x1,x-1) '
// ─────────────────────────────────────────────────────────────────────────────
class OmmWidget extends StatefulWidget {
  /// Сырой OMM-код (всё, что между кавычками)
  final String ommCode;

  /// Цвет фона canvas (опционально, по умолчанию прозрачный/тёмный)
  final Color backgroundColor;

  const OmmWidget({
    super.key,
    required this.ommCode,
    this.backgroundColor = const Color(0xFF1A1A2E),
  });

  @override
  State<OmmWidget> createState() => _OmmWidgetState();
}

class _OmmWidgetState extends State<OmmWidget> {
  late final WebViewController _controller;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.backgroundColor)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoaded = true);
        },
      ))
      ..loadHtmlString(_buildHtml());
  }

  String _colorToCss(Color c) {
    return 'rgb(${c.red},${c.green},${c.blue})';
  }

  String _buildHtml() {
    final bg = _colorToCss(widget.backgroundColor);
    // Экранируем одинарные кавычки в OMM-коде для вставки в JS-строку
    final escapedCode = widget.ommCode
        .replaceAll('\\', '\\\\')
        .replaceAll('`', '\\`');

    return '''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html, body { width:100%; height:100%; background:$bg; overflow:hidden; }
  omm-model { width:100%; height:100%; display:block; }
</style>
</head>
<body>
<omm-model freer autorate id="m"></omm-model>
<script>
${_getOmmCoreJs()}
document.getElementById('m').setAttribute('src', \`${escapedCode}\`);
</script>
</body>
</html>''';
  }

  /// Возвращает содержимое omm-core.js, встроенное как строка.
  /// Файл подключается через assets (см. pubspec.yaml: assets/omm-core.js).
  /// Для упрощения интеграции omm-core.js грузится через rootBundle
  /// и кэшируется в статическом поле.
  static String? _cachedOmmCoreJs;

  String _getOmmCoreJs() {
    // В реальном коде здесь нужно синхронно отдать содержимое omm-core.js.
    // Т.к. loadHtmlString вызывается в initState (синхронно),
    // используем отдельный метод _buildHtmlAsync() ниже.
    // Здесь оставляем заглушку — реальный JS подставляется через _buildHtmlAsync.
    return _cachedOmmCoreJs ?? '/* omm-core not loaded yet */';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadOmmCoreAndReload();
  }

  Future<void> _loadOmmCoreAndReload() async {
    if (_OmmWidgetState._cachedOmmCoreJs != null) return;
    try {
      final js = await DefaultAssetBundle.of(context)
          .loadString('assets/omm-core.js');
      _OmmWidgetState._cachedOmmCoreJs = js;
      // Перезагружаем HTML уже с реальным JS
      await _controller.loadHtmlString(_buildHtml());
    } catch (e) {
      debugPrint('OmmWidget: не удалось загрузить omm-core.js: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (!_isLoaded)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}
