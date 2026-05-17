import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Модели
// ─────────────────────────────────────────────────────────────────────────────

/// Сообщение в mesh-сети
class MeshMessage {
  /// Уникальный ID сообщения (используется для дедупликации при ретрансляции)
  final String id;

  /// ID узла-отправителя (MAC-адрес BT в hex без разделителей)
  final String originId;

  /// ID получателя (MAC или '*' для broadcast)
  final String targetId;

  /// Текстовое содержимое
  final String text;

  /// Отображаемое имя отправителя
  final String senderName;

  /// Временная метка (Unix ms, UTC)
  final int timestamp;

  /// TTL — сколько хопов сообщение ещё может пройти
  final int ttl;

  /// Признак того, что сообщение пришло через relay (не от прямого собеседника)
  final bool isRelayed;

  const MeshMessage({
    required this.id,
    required this.originId,
    required this.targetId,
    required this.text,
    required this.senderName,
    required this.timestamp,
    this.ttl = 5,
    this.isRelayed = false,
  });

  factory MeshMessage.fromJson(Map<String, dynamic> j) => MeshMessage(
        id: j['id'] as String,
        originId: j['originId'] as String,
        targetId: j['targetId'] as String,
        text: j['text'] as String,
        senderName: j['senderName'] as String,
        timestamp: j['timestamp'] as int,
        ttl: (j['ttl'] as int?) ?? 5,
        isRelayed: (j['isRelayed'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'originId': originId,
        'targetId': targetId,
        'text': text,
        'senderName': senderName,
        'timestamp': timestamp,
        'ttl': ttl,
        'isRelayed': isRelayed,
      };

  MeshMessage copyWith({int? ttl, bool? isRelayed}) => MeshMessage(
        id: id,
        originId: originId,
        targetId: targetId,
        text: text,
        senderName: senderName,
        timestamp: timestamp,
        ttl: ttl ?? this.ttl,
        isRelayed: isRelayed ?? this.isRelayed,
      );
}

/// Узел (peer) в mesh-сети
class MeshPeer {
  final String address; // BT MAC
  final String name;    // видимое имя
  final DateTime lastSeen;
  final bool isConnected;

  const MeshPeer({
    required this.address,
    required this.name,
    required this.lastSeen,
    this.isConnected = false,
  });

  MeshPeer copyWith({bool? isConnected, DateTime? lastSeen}) => MeshPeer(
        address: address,
        name: name,
        lastSeen: lastSeen ?? this.lastSeen,
        isConnected: isConnected ?? this.isConnected,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bluetooth Mesh Transport — синглтон
// ─────────────────────────────────────────────────────────────────────────────

/// Простой Bluetooth mesh для P2P-сообщений без интернета.
///
/// Принцип работы:
///  1. Устройство делает discovery, подключается ко всем обнаруженным пирам.
///  2. Каждое сообщение содержит TTL; при пересылке TTL уменьшается.
///  3. Уже виденные ID сообщений кешируются → дедупликация петель.
///  4. Сообщение с targetId == '*' → broadcast; иначе unicast.
///
/// Ограничение: `flutter_bluetooth_serial` — Android only.
/// На iOS нужен CoreBluetooth (BLE) — заглушка предусмотрена.
class BluetoothMeshTransport {
  static final BluetoothMeshTransport _instance =
      BluetoothMeshTransport._internal();
  factory BluetoothMeshTransport() => _instance;
  BluetoothMeshTransport._internal();

  // ── Состояние ────────────────────────────────────────────────────────────

  bool _running = false;
  String? _localAddress;
  String _localName = 'Komet';

  /// Активные соединения: address → соединение
  final Map<String, BluetoothConnection> _connections = {};

  /// Накопленные буферы входящих данных (по пирам)
  final Map<String, List<int>> _buffers = {};

  /// Кеш ID уже обработанных сообщений (дедупликация)
  final Set<String> _seenIds = {};

  /// Известные пиры (подключённые + обнаруженные)
  final Map<String, MeshPeer> _peers = {};

  // ── Стримы ───────────────────────────────────────────────────────────────

  final StreamController<MeshMessage> _incomingCtrl =
      StreamController<MeshMessage>.broadcast();

  final StreamController<List<MeshPeer>> _peersCtrl =
      StreamController<List<MeshPeer>>.broadcast();

  /// Входящие mesh-сообщения адресованные нам или broadcast
  Stream<MeshMessage> get incoming => _incomingCtrl.stream;

  /// Список известных пиров (обновляется при изменениях)
  Stream<List<MeshPeer>> get peers => _peersCtrl.stream;

  List<MeshPeer> get currentPeers => List.unmodifiable(_peers.values);
  bool get isRunning => _running;
  String? get localAddress => _localAddress;

  // ── Таймеры ──────────────────────────────────────────────────────────────

  Timer? _discoveryTimer;
  Timer? _cleanupTimer;

  // ── UUID сервиса (SPP-подобный профиль) ──────────────────────────────────

  static const String _kometUuid = '00001101-0000-1000-8000-00805F9B34FB'; // SPP

  // ─────────────────────────────────────────────
  // Запуск / остановка
  // ─────────────────────────────────────────────

  /// Запустить mesh.
  /// [displayName] — имя, видимое другим устройствам.
  Future<MeshStartResult> start({String displayName = 'Komet'}) async {
    if (_running) return MeshStartResult.alreadyRunning;

    try {
      final bt = FlutterBluetoothSerial.instance;

      // Проверяем доступность
      final isAvailable = await bt.isAvailable;
      if (isAvailable != true) return MeshStartResult.notAvailable;

      final isEnabled = await bt.isEnabled;
      if (isEnabled != true) {
        final enabled = await bt.requestEnable();
        if (enabled != true) return MeshStartResult.disabled;
      }

      _localName = displayName;
      final info = await bt.getLocalName();
      _localAddress = (await bt.address) ?? 'unknown';

      _running = true;

      // Периодический discovery каждые 30 с
      _discoveryTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _runDiscovery(),
      );

      // Очистка устаревших пиров каждые 2 мин
      _cleanupTimer = Timer.periodic(
        const Duration(minutes: 2),
        (_) => _cleanupPeers(),
      );

      // Первый discovery сразу
      _runDiscovery();

      debugPrint('[BtMesh] Started. Local: $_localAddress ($info)');
      return MeshStartResult.ok;
    } catch (e) {
      debugPrint('[BtMesh] Start error: $e');
      return MeshStartResult.error;
    }
  }

  Future<void> stop() async {
    _running = false;
    _discoveryTimer?.cancel();
    _cleanupTimer?.cancel();

    for (final conn in _connections.values) {
      try { conn.dispose(); } catch (_) {}
    }
    _connections.clear();
    _buffers.clear();
    debugPrint('[BtMesh] Stopped');
  }

  // ─────────────────────────────────────────────
  // Discovery
  // ─────────────────────────────────────────────

  Future<void> _runDiscovery() async {
    if (!_running) return;
    try {
      final results = await FlutterBluetoothSerial.instance
          .startDiscovery()
          .toList()
          .timeout(const Duration(seconds: 15), onTimeout: () => []);

      for (final r in results) {
        final addr = r.device.address;
        final name = r.device.name ?? addr;

        // Фильтрация: подключаемся только к устройствам с UUID нашего сервиса
        // (проверяем список UUID в discovery result)
        final uuids = r.device.uuids ?? [];
        final isKometPeer = uuids.isEmpty || // старый Android не отдаёт UUID
            uuids.any((u) => u.toString().toLowerCase() == _kometUuid);

        if (!isKometPeer) continue;

        _peers[addr] = MeshPeer(
          address: addr,
          name: name,
          lastSeen: DateTime.now(),
          isConnected: _connections.containsKey(addr),
        );

        // Подключаемся если ещё не подключены
        if (!_connections.containsKey(addr)) {
          _connectToPeer(addr, name);
        }
      }

      _notifyPeers();
    } catch (e) {
      debugPrint('[BtMesh] Discovery error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // Подключение к пиру
  // ─────────────────────────────────────────────

  Future<void> _connectToPeer(String address, String name) async {
    if (_connections.containsKey(address)) return;
    try {
      final conn = await BluetoothConnection.toAddress(address)
          .timeout(const Duration(seconds: 8));

      _connections[address] = conn;
      _buffers[address] = [];

      final peer = _peers[address];
      if (peer != null) {
        _peers[address] = peer.copyWith(isConnected: true, lastSeen: DateTime.now());
        _notifyPeers();
      }

      debugPrint('[BtMesh] Connected to $name ($address)');

      // Слушаем входящие данные
      conn.input!.listen(
        (data) => _onData(address, data),
        onDone: () => _onDisconnect(address),
        onError: (_) => _onDisconnect(address),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[BtMesh] Connect to $address failed: $e');
    }
  }

  // ─────────────────────────────────────────────
  // Входящие данные
  // ─────────────────────────────────────────────

  void _onData(String address, Uint8List data) {
    final buf = _buffers[address] ??= [];
    buf.addAll(data);

    // Протокол: JSON-объект завершается символом '\n' (0x0A)
    while (buf.contains(0x0A)) {
      final idx = buf.indexOf(0x0A);
      final line = utf8.decode(buf.sublist(0, idx), allowMalformed: true);
      buf.removeRange(0, idx + 1);

      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        _handleIncomingJson(json);
      } catch (e) {
        debugPrint('[BtMesh] Parse error from $address: $e');
      }
    }
  }

  void _handleIncomingJson(Map<String, dynamic> json) {
    final msg = MeshMessage.fromJson(json);

    // Дедупликация
    if (_seenIds.contains(msg.id)) return;
    _seenIds.add(msg.id);
    if (_seenIds.length > 500) {
      // Ограничиваем размер кеша
      _seenIds.remove(_seenIds.first);
    }

    final localAddr = _localAddress ?? '';

    // Это сообщение для нас или broadcast?
    if (msg.targetId == '*' || msg.targetId == localAddr) {
      _incomingCtrl.add(msg);
    }

    // Ретрансляция если TTL > 1 и мы не адресат
    if (msg.ttl > 1 && msg.targetId != localAddr) {
      final relayed = msg.copyWith(ttl: msg.ttl - 1, isRelayed: true);
      _relay(relayed, except: msg.originId);
    }
  }

  void _relay(MeshMessage msg, {String? except}) {
    final line = '${jsonEncode(msg.toJson())}\n';
    final bytes = utf8.encode(line);
    for (final entry in _connections.entries) {
      if (entry.key == except) continue;
      try {
        entry.value.output.add(Uint8List.fromList(bytes));
      } catch (_) {}
    }
  }

  // ─────────────────────────────────────────────
  // Отправка сообщения
  // ─────────────────────────────────────────────

  /// Отправить сообщение в mesh.
  /// [targetId] == null → broadcast ('*'), иначе MAC конкретного устройства.
  Future<MeshSendResult> send({
    required String text,
    required String senderName,
    String? targetId,
  }) async {
    if (!_running) return MeshSendResult.notRunning;
    if (_connections.isEmpty) return MeshSendResult.noPeers;

    final msg = MeshMessage(
      id: _generateId(),
      originId: _localAddress ?? 'unknown',
      targetId: targetId ?? '*',
      text: text,
      senderName: senderName,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      ttl: 5,
    );

    // Помечаем как виденное, чтобы не получить обратно
    _seenIds.add(msg.id);

    final line = '${jsonEncode(msg.toJson())}\n';
    final bytes = Uint8List.fromList(utf8.encode(line));

    int sent = 0;
    for (final conn in _connections.values) {
      try {
        conn.output.add(bytes);
        sent++;
      } catch (e) {
        debugPrint('[BtMesh] Send error: $e');
      }
    }

    return sent > 0 ? MeshSendResult.ok : MeshSendResult.noPeers;
  }

  // ─────────────────────────────────────────────
  // Утилиты
  // ─────────────────────────────────────────────

  void _onDisconnect(String address) {
    _connections.remove(address);
    _buffers.remove(address);
    final peer = _peers[address];
    if (peer != null) {
      _peers[address] = peer.copyWith(isConnected: false);
      _notifyPeers();
    }
    debugPrint('[BtMesh] Disconnected from $address');
  }

  void _cleanupPeers() {
    final threshold = DateTime.now().subtract(const Duration(minutes: 10));
    _peers.removeWhere(
      (addr, peer) => !peer.isConnected && peer.lastSeen.isBefore(threshold),
    );
    _notifyPeers();
  }

  void _notifyPeers() {
    _peersCtrl.add(List.unmodifiable(_peers.values));
  }

  String _generateId() {
    final rng = Random.secure();
    return List.generate(16, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Результаты операций
// ─────────────────────────────────────────────────────────────────────────────

enum MeshStartResult {
  ok,
  alreadyRunning,
  notAvailable,
  disabled,
  error,
}

enum MeshSendResult {
  ok,
  notRunning,
  noPeers,
}
