import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gwid/mesh/bluetooth_mesh_transport.dart';

/// Экран P2P-чата через Bluetooth Mesh (без интернета)
class MeshChatScreen extends StatefulWidget {
  const MeshChatScreen({super.key});

  @override
  State<MeshChatScreen> createState() => _MeshChatScreenState();
}

class _MeshChatScreenState extends State<MeshChatScreen>
    with WidgetsBindingObserver {
  final BluetoothMeshTransport _mesh = BluetoothMeshTransport();
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<MeshMessage> _messages = [];
  List<MeshPeer> _peers = [];

  StreamSubscription<MeshMessage>? _msgSub;
  StreamSubscription<List<MeshPeer>>? _peersSub;

  bool _starting = false;
  bool _started = false;
  String? _statusError;

  String _myName = 'Я';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _started = _mesh.isRunning;
    if (_started) _subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _msgSub?.cancel();
    _peersSub?.cancel();
    _textCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _subscribe() {
    _msgSub = _mesh.incoming.listen((msg) {
      setState(() => _messages.add(msg));
      _scrollToBottom();
    });
    _peersSub = _mesh.peers.listen((peers) {
      setState(() => _peers = peers);
    });
    setState(() => _peers = _mesh.currentPeers);
  }

  Future<void> _startMesh() async {
    setState(() {
      _starting = true;
      _statusError = null;
    });

    final result = await _mesh.start(displayName: _myName);

    switch (result) {
      case MeshStartResult.ok:
        setState(() {
          _started = true;
          _starting = false;
        });
        _subscribe();
        break;
      case MeshStartResult.alreadyRunning:
        setState(() {
          _started = true;
          _starting = false;
        });
        _subscribe();
        break;
      case MeshStartResult.notAvailable:
        setState(() {
          _starting = false;
          _statusError = 'Bluetooth недоступен на этом устройстве';
        });
        break;
      case MeshStartResult.disabled:
        setState(() {
          _starting = false;
          _statusError = 'Bluetooth выключен. Разрешите его и попробуйте снова';
        });
        break;
      case MeshStartResult.error:
        setState(() {
          _starting = false;
          _statusError = 'Не удалось запустить mesh. Проверьте разрешения';
        });
        break;
    }
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    _textCtrl.clear();

    final result = await _mesh.send(text: text, senderName: _myName);
    if (result == MeshSendResult.noPeers) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет подключённых устройств рядом')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth, size: 18, color: colors.primary),
                const SizedBox(width: 6),
                Text(
                  'Mesh-чат',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Text(
              _started
                  ? '${_peers.where((p) => p.isConnected).length} устройств в сети'
                  : 'Без интернета · P2P Bluetooth',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        actions: [
          if (_started)
            IconButton(
              icon: const Icon(Icons.people_outline_rounded),
              tooltip: 'Устройства',
              onPressed: () => _showPeersSheet(context),
            ),
        ],
      ),
      body: !_started ? _buildStartScreen(theme, colors) : _buildChat(theme, colors),
    );
  }

  Widget _buildStartScreen(ThemeData theme, ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bluetooth_searching_rounded,
                  size: 44, color: colors.onPrimaryContainer),
            ),
            const SizedBox(height: 24),
            Text(
              'Bluetooth Mesh',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Общайтесь с людьми рядом без интернета.\n'
              'Сообщения передаются через Bluetooth-сеть из устройств.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (_statusError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _statusError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            // Поле имени
            TextField(
              decoration: const InputDecoration(
                labelText: 'Ваше имя в mesh-сети',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _myName = v.trim().isEmpty ? 'Я' : v,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _starting ? null : _startMesh,
                icon: _starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bluetooth_connected_rounded),
                label: Text(_starting ? 'Запуск...' : 'Начать'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChat(ThemeData theme, ColorScheme colors) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? _buildEmptyChat(theme, colors)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _buildBubble(_messages[i], theme, colors),
                ),
        ),
        _buildInput(theme, colors),
      ],
    );
  }

  Widget _buildEmptyChat(ThemeData theme, ColorScheme colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cell_tower, size: 48,
              color: colors.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            'Сеть активна',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.4),
            ),
          ),
          Text(
            'Отправьте первое сообщение в эфир',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(MeshMessage msg, ThemeData theme, ColorScheme colors) {
    final isMe = msg.originId == (_mesh.localAddress ?? '');
    final time = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? colors.primaryContainer : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    msg.senderName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (msg.isRelayed) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.sync_rounded,
                        size: 12,
                        color: colors.onSurface.withValues(alpha: 0.4)),
                  ],
                ],
              ),
              const SizedBox(height: 2),
            ],
            Text(
              msg.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isMe ? colors.onPrimaryContainer : colors.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              timeStr,
              style: theme.textTheme.labelSmall?.copyWith(
                color: (isMe ? colors.onPrimaryContainer : colors.onSurface)
                    .withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(ThemeData theme, ColorScheme colors) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textCtrl,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Сообщение в эфир...',
                filled: true,
                fillColor: colors.surfaceContainerHighest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _send,
            icon: const Icon(Icons.send_rounded),
            style: IconButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showPeersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Устройства в сети',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 12),
              if (_peers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'Поиск устройств...',
                      style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.5)),
                    ),
                  ),
                )
              else
                ..._peers.map(
                  (p) => ListTile(
                    leading: Icon(
                      p.isConnected
                          ? Icons.bluetooth_connected_rounded
                          : Icons.bluetooth_rounded,
                      color: p.isConnected ? colors.primary : null,
                    ),
                    title: Text(p.name),
                    subtitle: Text(p.deviceId),
                    trailing: p.isConnected
                        ? const Icon(Icons.circle, color: Colors.green, size: 10)
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
