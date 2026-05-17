import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ── UUIDs (Komet custom BLE GATT service) ────────────────────────────────────
const _kServiceUuid = '12340000-1234-1234-1234-123456789abc';
const _kCharUuid    = '12340001-1234-1234-1234-123456789abc';
const _kChunkSize   = 20; // safe BLE MTU without negotiation

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class MeshMessage {
  final String id;
  final String originId;
  final String targetId;
  final String text;
  final String senderName;
  final int    timestamp;
  final int    ttl;
  final bool   isRelayed;

  const MeshMessage({
    required this.id,
    required this.originId,
    required this.targetId,
    required this.text,
    required this.senderName,
    required this.timestamp,
    this.ttl       = 5,
    this.isRelayed = false,
  });

  factory MeshMessage.fromJson(Map<String, dynamic> j) => MeshMessage(
        id:         j['id'] as String,
        originId:   j['o']  as String,
        targetId:   j['t']  as String,
        text:       j['x']  as String,
        senderName: j['n']  as String,
        timestamp:  j['ts'] as int,
        ttl:        (j['ttl'] as int?) ?? 5,
        isRelayed:  (j['r'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'o': originId, 't': targetId,
        'x': text, 'n': senderName, 'ts': timestamp,
        'ttl': ttl, 'r': isRelayed,
      };

  MeshMessage copyWith({int? ttl, bool? isRelayed}) => MeshMessage(
        id: id, originId: originId, targetId: targetId,
        text: text, senderName: senderName, timestamp: timestamp,
        ttl: ttl ?? this.ttl, isRelayed: isRelayed ?? this.isRelayed,
      );
}

class MeshPeer {
  final String   deviceId;
  final String   name;
  final DateTime lastSeen;
  final bool     isConnected;

  const MeshPeer({
    required this.deviceId,
    required this.name,
    required this.lastSeen,
    this.isConnected = false,
  });

  MeshPeer copyWith({bool? isConnected, DateTime? lastSeen}) => MeshPeer(
        deviceId: deviceId, name: name,
        lastSeen:    lastSeen    ?? this.lastSeen,
        isConnected: isConnected ?? this.isConnected,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal per-peer connection state
// ─────────────────────────────────────────────────────────────────────────────

class _PeerConn {
  final BluetoothDevice          device;
  BluetoothCharacteristic?       char;
  final List<int>                rxBuf = [];
  StreamSubscription<dynamic>?   notifySub;
  StreamSubscription<dynamic>?   stateSub;

  _PeerConn(this.device);
}

// ─────────────────────────────────────────────────────────────────────────────
// BluetoothMeshTransport
// ─────────────────────────────────────────────────────────────────────────────

class BluetoothMeshTransport {
  static final BluetoothMeshTransport _instance =
      BluetoothMeshTransport._internal();
  factory BluetoothMeshTransport() => _instance;
  BluetoothMeshTransport._internal();

  bool   _running   = false;
  String _localId   = '';
  String _localName = 'Komet';

  final Map<String, _PeerConn> _peers      = {};
  final Set<String>            _seenIds    = {};
  final Set<String>            _connecting = {};

  StreamSubscription<dynamic>? _scanSub;
  Timer? _rescanTimer;
  Timer? _cleanupTimer;

  final _inCtrl    = StreamController<MeshMessage>.broadcast();
  final _peersCtrl = StreamController<List<MeshPeer>>.broadcast();

  Stream<MeshMessage>    get incoming     => _inCtrl.stream;
  Stream<List<MeshPeer>> get peers        => _peersCtrl.stream;
  bool                   get isRunning    => _running;
  String                 get localAddress => _localId;

  List<MeshPeer> get currentPeers => _peers.values.map((c) {
        final n = c.device.platformName;
        return MeshPeer(
          deviceId:    c.device.remoteId.str,
          name:        n.isEmpty ? c.device.remoteId.str : n,
          lastSeen:    DateTime.now(),
          isConnected: c.device.isConnected,
        );
      }).toList();

  // ── Start ─────────────────────────────────────────────────────────────────

  Future<MeshStartResult> start({String displayName = 'Komet'}) async {
    if (_running) return MeshStartResult.alreadyRunning;

    _localName = displayName;
    _localId   = _genId();

    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.unavailable) {
      return MeshStartResult.notAvailable;
    }
    if (state != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        return MeshStartResult.disabled;
      }
    }

    _running = true;
    _startScan();

    _rescanTimer  = Timer.periodic(const Duration(seconds: 25), (_) { if (_running) _startScan(); });
    _cleanupTimer = Timer.periodic(const Duration(minutes: 2),  (_) { _cleanupStale(); });

    debugPrint('[BtMesh] Started localId=$_localId');
    return MeshStartResult.ok;
  }

  Future<void> stop() async {
    _running = false;
    _rescanTimer?.cancel();
    _cleanupTimer?.cancel();
    _scanSub?.cancel();
    await FlutterBluePlus.stopScan().catchError((_) {});
    for (final c in _peers.values) {
      c.notifySub?.cancel();
      c.stateSub?.cancel();
      try { await c.device.disconnect(); } catch (_) {}
    }
    _peers.clear();
    _connecting.clear();
    debugPrint('[BtMesh] Stopped');
  }

  // ── Scan ──────────────────────────────────────────────────────────────────

  void _startScan() {
    FlutterBluePlus.stopScan().catchError((_) {});
    _scanSub?.cancel();

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        if (!_peers.containsKey(id) && !_connecting.contains(id)) {
          _connectToPeer(r.device);
        }
      }
    });

    FlutterBluePlus.startScan(
      withServices: [Guid(_kServiceUuid)],
      timeout: const Duration(seconds: 20),
    ).catchError((e) => debugPrint('[BtMesh] Scan error: $e'));
  }

  // ── Connect ───────────────────────────────────────────────────────────────

  Future<void> _connectToPeer(BluetoothDevice device) async {
    final id = device.remoteId.str;
    if (_peers.containsKey(id) || _connecting.contains(id)) return;
    _connecting.add(id);

    try {
      await device.connect(timeout: const Duration(seconds: 8));
      await device.requestMtu(128).catchError((_) {});

      final services = await device.discoverServices();
      final svc = services.cast<BluetoothService?>().firstWhere(
            (s) => s!.uuid == Guid(_kServiceUuid),
            orElse: () => null,
          );
      if (svc == null) { await device.disconnect(); return; }

      final char = svc.characteristics.cast<BluetoothCharacteristic?>().firstWhere(
            (c) => c!.uuid == Guid(_kCharUuid),
            orElse: () => null,
          );
      if (char == null) { await device.disconnect(); return; }

      final conn = _PeerConn(device);
      conn.char = char;
      _peers[id] = conn;

      await char.setNotifyValue(true);
      conn.notifySub = char.onValueReceived.listen(
        (data) => _onChunk(id, data),
        onError: (_) => _onDisconnect(id),
        onDone:  () => _onDisconnect(id),
        cancelOnError: true,
      );
      conn.stateSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _onDisconnect(id);
      });

      _notifyPeers();
      debugPrint('[BtMesh] Connected to ${device.platformName} ($id)');
    } catch (e) {
      debugPrint('[BtMesh] Connect $id failed: $e');
      try { await device.disconnect(); } catch (_) {}
    } finally {
      _connecting.remove(id);
    }
  }

  // ── Incoming chunks ───────────────────────────────────────────────────────

  void _onChunk(String peerId, List<int> data) {
    final conn = _peers[peerId];
    if (conn == null) return;

    if (data.isNotEmpty && data.last == 0x00) {
      conn.rxBuf.addAll(data.sublist(0, data.length - 1));
      _processPacket(peerId, List.of(conn.rxBuf));
      conn.rxBuf.clear();
    } else {
      conn.rxBuf.addAll(data);
    }
  }

  void _processPacket(String peerId, List<int> bytes) {
    try {
      final msg = MeshMessage.fromJson(
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);

      if (_seenIds.contains(msg.id)) return;
      _seenIds.add(msg.id);
      if (_seenIds.length > 512) _seenIds.remove(_seenIds.first);

      if (msg.targetId == '*' || msg.targetId == _localId) {
        _inCtrl.add(msg);
      }
      if (msg.ttl > 1 && msg.targetId != _localId) {
        _relay(msg.copyWith(ttl: msg.ttl - 1, isRelayed: true), except: peerId);
      }
    } catch (e) {
      debugPrint('[BtMesh] Parse error from $peerId: $e');
    }
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<MeshSendResult> send({
    required String text,
    required String senderName,
    String? targetId,
  }) async {
    if (!_running) return MeshSendResult.notRunning;
    final live = _peers.values.where((c) => c.device.isConnected).toList();
    if (live.isEmpty) return MeshSendResult.noPeers;

    final msg = MeshMessage(
      id: _genId(), originId: _localId, targetId: targetId ?? '*',
      text: text, senderName: senderName,
      timestamp: DateTime.now().millisecondsSinceEpoch, ttl: 5,
    );
    _seenIds.add(msg.id);

    final bytes = utf8.encode(jsonEncode(msg.toJson()));
    int sent = 0;
    for (final c in live) {
      if (await _writeChunked(c, bytes)) sent++;
    }
    return sent > 0 ? MeshSendResult.ok : MeshSendResult.noPeers;
  }

  Future<bool> _writeChunked(_PeerConn conn, List<int> bytes) async {
    if (conn.char == null) return false;
    try {
      for (int i = 0; i < bytes.length; i += _kChunkSize) {
        final end    = (i + _kChunkSize < bytes.length) ? i + _kChunkSize : bytes.length;
        final isLast = end == bytes.length;
        final chunk  = Uint8List.fromList(
          isLast ? [...bytes.sublist(i, end), 0x00] : bytes.sublist(i, end),
        );
        await conn.char!.write(chunk, withoutResponse: true);
      }
      return true;
    } catch (e) {
      debugPrint('[BtMesh] Write error: $e');
      return false;
    }
  }

  void _relay(MeshMessage msg, {String? except}) {
    final bytes = utf8.encode(jsonEncode(msg.toJson()));
    for (final e in _peers.entries) {
      if (e.key == except || !e.value.device.isConnected) continue;
      _writeChunked(e.value, bytes);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _onDisconnect(String id) {
    final c = _peers.remove(id);
    c?.notifySub?.cancel();
    c?.stateSub?.cancel();
    _notifyPeers();
    debugPrint('[BtMesh] Disconnected: $id');
  }

  void _cleanupStale() {
    _peers.removeWhere((_, c) => !c.device.isConnected);
    _notifyPeers();
  }

  void _notifyPeers() => _peersCtrl.add(currentPeers);

  String _genId() => List.generate(
        16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
}

enum MeshStartResult { ok, alreadyRunning, notAvailable, disabled, error }
enum MeshSendResult  { ok, notRunning, noPeers }
