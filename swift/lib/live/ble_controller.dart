import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_codec.dart';

enum CommandAckState { acknowledged, rejected, timeout }

class BleLogEntry {
  BleLogEntry({
    required this.timestamp,
    required this.direction,
    required this.hex,
    required this.decoded,
    this.note,
  });

  final DateTime timestamp;
  final String direction;
  final String hex;
  final Map<String, dynamic> decoded;
  final String? note;
}

class BleController extends ChangeNotifier {
  static const _logDirKey = 'ble_log_dir';
  static const _defaultProjectLogDir = '/Users/globel/r4830_project/swift/logs';
  static const _rxCharPrefPrefix = 'ble_rx_char:';
  static const _txCharPrefPrefix = 'ble_tx_char:';

  BleController({bool bindPlatformStreams = true}) {
    if (bindPlatformStreams) {
      _bindPlatformStreams();
    }
  }

  BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;
  bool isScanning = false;
  List<ScanResult> scanResults = [];
  BluetoothDevice? device;
  BluetoothConnectionState connectionState =
      BluetoothConnectionState.disconnected;
  List<BluetoothService> services = [];
  List<BluetoothCharacteristic> allChars = [];
  List<BluetoothCharacteristic> notifyChars = [];
  List<BluetoothCharacteristic> writeChars = [];
  BluetoothCharacteristic? rxChar;
  BluetoothCharacteristic? txChar;
  bool isSubscribed = false;
  bool keepaliveEnabled = false;
  double keepaliveSeconds = 1.0;
  bool telemetryPollingEnabled = true;
  double telemetryPollSeconds = 2.0;
  String authPassword = '';
  bool autoQuickStartOnConnect = true;
  final List<BleLogEntry> logs = [];
  String? lastError;
  String? logDirectory;
  String? logFilePath;
  String? logJsonlPath;
  bool logToFileEnabled = false;

  bool get isConnected => connectionState == BluetoothConnectionState.connected;

  List<BleLogEntry> get rxLogs {
    final out = <BleLogEntry>[];
    for (final entry in logs) {
      if (entry.direction == 'RX') out.add(entry);
    }
    return out;
  }

  List<BleLogEntry> get txLogs {
    final out = <BleLogEntry>[];
    for (final entry in logs) {
      if (entry.direction == 'TX') out.add(entry);
    }
    return out;
  }

  StreamSubscription? _adapterSub;
  StreamSubscription? _scanSub;
  StreamSubscription? _isScanningSub;
  StreamSubscription? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<List<int>>? _notifyLastValueSub;
  Timer? _keepaliveTimer;
  Timer? _telemetryPollTimer;
  DateTime? lastRxAt;
  String? _recentRxHex;
  DateTime? _recentRxStamp;

  void _bindPlatformStreams() {
    try {
      _adapterSub = FlutterBluePlus.adapterState.listen(
        (state) {
          adapterState = state;
          notifyListeners();
        },
        onError: (Object error) {
          lastError = 'BLE adapter stream unavailable: $error';
          notifyListeners();
        },
      );
    } catch (e) {
      lastError = 'BLE adapter stream unavailable: $e';
    }

    try {
      _scanSub = FlutterBluePlus.scanResults.listen(
        (results) {
          final sorted = List<ScanResult>.from(results)
            ..sort((a, b) => b.rssi.compareTo(a.rssi));
          scanResults = sorted;
          notifyListeners();
        },
        onError: (Object error) {
          lastError = 'BLE scan stream unavailable: $error';
          notifyListeners();
        },
      );
    } catch (e) {
      lastError = 'BLE scan stream unavailable: $e';
    }

    try {
      _isScanningSub = FlutterBluePlus.isScanning.listen(
        (value) {
          isScanning = value;
          notifyListeners();
        },
        onError: (Object error) {
          lastError = 'BLE scan state unavailable: $error';
          notifyListeners();
        },
      );
    } catch (e) {
      lastError = 'BLE scan state unavailable: $e';
    }
  }

  @override
  void dispose() {
    _keepaliveTimer?.cancel();
    _telemetryPollTimer?.cancel();
    _notifySub?.cancel();
    _notifyLastValueSub?.cancel();
    _connectionSub?.cancel();
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    _adapterSub?.cancel();
    super.dispose();
  }

  Future<void> startScan() async {
    lastError = null;
    try {
      scanResults = [];
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    } catch (e) {
      lastError = 'Scan failed: $e';
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    lastError = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      lastError = 'Stop scan failed: $e';
      notifyListeners();
    }
  }

  Future<void> connect(BluetoothDevice target) async {
    lastError = null;
    device = target;
    notifyListeners();

    _connectionSub?.cancel();
    _connectionSub = target.connectionState.listen((state) {
      connectionState = state;
      if (state == BluetoothConnectionState.disconnected) {
        _notifySub?.cancel();
        _notifySub = null;
        _notifyLastValueSub?.cancel();
        _notifyLastValueSub = null;
        isSubscribed = false;
        keepaliveEnabled = false;
        _telemetryPollTimer?.cancel();
        _telemetryPollTimer = null;
        _keepaliveTimer?.cancel();
        _keepaliveTimer = null;
      }
      notifyListeners();
    });

    try {
      await target.connect(
        license: License.free,
        timeout: const Duration(seconds: 20),
        autoConnect: false,
      );
      await discoverServices();
      if (autoQuickStartOnConnect) {
        await quickStart();
      }
    } catch (e) {
      lastError = 'Connect failed: $e';
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    lastError = null;
    final target = device;
    if (target == null) return;
    try {
      await target.disconnect();
      device = null;
      services = [];
      allChars = [];
      notifyChars = [];
      writeChars = [];
      rxChar = null;
      txChar = null;
      isSubscribed = false;
      keepaliveEnabled = false;
      _telemetryPollTimer?.cancel();
      _telemetryPollTimer = null;
      _keepaliveTimer?.cancel();
      _keepaliveTimer = null;
      notifyListeners();
    } catch (e) {
      lastError = 'Disconnect failed: $e';
      notifyListeners();
    }
  }

  Future<void> discoverServices() async {
    lastError = null;
    final target = device;
    if (target == null) return;
    try {
      services = await target.discoverServices();
      _rebuildCharacteristics();
      await _restoreCharacteristicSelection();
      _autoSelectPreferredIfNeeded();
      _persistCharacteristicSelection(rx: true, tx: true);
      notifyListeners();
    } catch (e) {
      lastError = 'Discover services failed: $e';
      notifyListeners();
    }
  }

  void _rebuildCharacteristics() {
    allChars = [];
    notifyChars = [];
    writeChars = [];
    for (final service in services) {
      for (final chr in service.characteristics) {
        allChars.add(chr);
        final props = chr.properties;
        if (props.notify || props.indicate) {
          notifyChars.add(chr);
        }
        if (props.write || props.writeWithoutResponse) {
          writeChars.add(chr);
        }
      }
    }
    notifyChars = _dedupe(notifyChars);
    writeChars = _dedupe(writeChars);
    allChars = _dedupe(allChars);

    if (rxChar != null) {
      final match = _findMatch(rxChar!, notifyChars);
      rxChar = match;
    }
    if (txChar != null) {
      final match = _findMatch(txChar!, writeChars);
      txChar = match;
    }

    if (rxChar == null && notifyChars.length == 1) {
      rxChar = notifyChars.first;
    }
    if (txChar == null && writeChars.length == 1) {
      txChar = writeChars.first;
    }
  }

  void _autoSelectPreferredIfNeeded() {
    rxChar ??= _findByServiceAndUuid16(
      notifyChars,
      serviceUuid16: 'ffe1',
      charUuid16: 'ffe2',
      requireNotify: true,
    );
    rxChar ??= _findByServiceAndUuid16(
      allChars,
      serviceUuid16: 'ffe1',
      charUuid16: 'ffe2',
      requireNotify: true,
    );

    txChar ??= _findByServiceAndUuid16(
      writeChars,
      serviceUuid16: 'ffe1',
      charUuid16: 'ffe3',
      requireWrite: true,
    );
    txChar ??= _findByServiceAndUuid16(
      allChars,
      serviceUuid16: 'ffe1',
      charUuid16: 'ffe3',
      requireWrite: true,
    );

    rxChar ??= _findByUuid16(notifyChars, 'ffe2');
    rxChar ??= _findByUuid16(allChars, 'ffe2');
    txChar ??= _findByUuid16(writeChars, 'ffe3');
    txChar ??= _findByUuid16(allChars, 'ffe3');

    if (txChar == null && rxChar != null) {
      final rxService = _uuid16(rxChar!.serviceUuid.str);
      txChar = _firstWhereOrNull(
        writeChars,
        (chr) =>
            _uuid16(chr.serviceUuid.str) == rxService &&
            _charKey(chr) != _charKey(rxChar!),
      );
    }

    rxChar ??= notifyChars.isNotEmpty ? notifyChars.first : null;
    txChar ??= _firstWhereOrNull(
      writeChars,
      (chr) => rxChar == null || _charKey(chr) != _charKey(rxChar!),
    );
    txChar ??= writeChars.isNotEmpty ? writeChars.first : null;
    if (rxChar == null &&
        txChar != null &&
        (txChar!.properties.notify || txChar!.properties.indicate)) {
      rxChar = txChar;
    }
  }

  BluetoothCharacteristic? _findByUuid16(
    List<BluetoothCharacteristic> candidates,
    String uuid16,
  ) {
    final target = uuid16.toLowerCase();
    for (final chr in candidates) {
      if (_uuid16(chr.characteristicUuid.str) == target) {
        return chr;
      }
    }
    return null;
  }

  BluetoothCharacteristic? _findByServiceAndUuid16(
    List<BluetoothCharacteristic> candidates, {
    required String serviceUuid16,
    required String charUuid16,
    bool requireNotify = false,
    bool requireWrite = false,
  }) {
    final serviceTarget = serviceUuid16.toLowerCase();
    final charTarget = charUuid16.toLowerCase();
    for (final chr in candidates) {
      final props = chr.properties;
      if (requireNotify && !(props.notify || props.indicate)) continue;
      if (requireWrite && !(props.write || props.writeWithoutResponse)) {
        continue;
      }
      final serviceMatch = _uuid16(chr.serviceUuid.str) == serviceTarget;
      final charMatch = _uuid16(chr.characteristicUuid.str) == charTarget;
      if (serviceMatch && charMatch) return chr;
    }
    return null;
  }

  BluetoothCharacteristic? _firstWhereOrNull(
    List<BluetoothCharacteristic> candidates,
    bool Function(BluetoothCharacteristic) test,
  ) {
    for (final chr in candidates) {
      if (test(chr)) return chr;
    }
    return null;
  }

  String _uuid16(String raw) {
    final lower = raw.toLowerCase();
    final match = RegExp(
      r'([0-9a-f]{4})(?:-0000-1000-8000-00805f9b34fb)?$',
    ).firstMatch(lower);
    return match?.group(1) ?? lower;
  }

  String _charKey(BluetoothCharacteristic chr) {
    final primary = chr.primaryServiceUuid?.str ?? '';
    return '$primary|${chr.serviceUuid.str}|${chr.characteristicUuid.str}|${chr.instanceId}';
  }

  BluetoothCharacteristic? _findMatch(
    BluetoothCharacteristic selected,
    List<BluetoothCharacteristic> candidates,
  ) {
    final key = _charKey(selected);
    for (final chr in candidates) {
      if (_charKey(chr) == key) return chr;
    }
    return null;
  }

  List<BluetoothCharacteristic> _dedupe(List<BluetoothCharacteristic> input) {
    final map = <String, BluetoothCharacteristic>{};
    for (final chr in input) {
      map.putIfAbsent(_charKey(chr), () => chr);
    }
    return map.values.toList();
  }

  void selectRxChar(BluetoothCharacteristic? chr) {
    rxChar = chr;
    _persistCharacteristicSelection(rx: true);
    notifyListeners();
  }

  void selectTxChar(BluetoothCharacteristic? chr) {
    txChar = chr;
    _persistCharacteristicSelection(tx: true);
    notifyListeners();
  }

  Future<void> _restoreCharacteristicSelection() async {
    final target = device;
    if (target == null) return;
    final deviceId = target.remoteId.str;
    if (deviceId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final rxStored = prefs.getString('$_rxCharPrefPrefix$deviceId');
    final txStored = prefs.getString('$_txCharPrefPrefix$deviceId');

    if (rxStored != null && rxStored.isNotEmpty) {
      rxChar =
          _findByStoredPair(notifyChars, rxStored) ??
          _findByStoredPair(allChars, rxStored);
    }
    if (txStored != null && txStored.isNotEmpty) {
      txChar =
          _findByStoredPair(writeChars, txStored) ??
          _findByStoredPair(allChars, txStored);
    }
  }

  void _persistCharacteristicSelection({bool rx = false, bool tx = false}) {
    final target = device;
    if (target == null) return;
    final deviceId = target.remoteId.str;
    if (deviceId.isEmpty) return;
    unawaited(
      _persistCharacteristicSelectionImpl(
        deviceId,
        persistRx: rx,
        persistTx: tx,
      ),
    );
  }

  Future<void> _persistCharacteristicSelectionImpl(
    String deviceId, {
    required bool persistRx,
    required bool persistTx,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (persistRx) {
      if (rxChar == null) {
        await prefs.remove('$_rxCharPrefPrefix$deviceId');
      } else {
        await prefs.setString(
          '$_rxCharPrefPrefix$deviceId',
          _serviceCharPair(rxChar!),
        );
      }
    }
    if (persistTx) {
      if (txChar == null) {
        await prefs.remove('$_txCharPrefPrefix$deviceId');
      } else {
        await prefs.setString(
          '$_txCharPrefPrefix$deviceId',
          _serviceCharPair(txChar!),
        );
      }
    }
  }

  String _serviceCharPair(BluetoothCharacteristic chr) {
    return '${_uuid16(chr.serviceUuid.str)}|${_uuid16(chr.characteristicUuid.str)}';
  }

  BluetoothCharacteristic? _findByStoredPair(
    List<BluetoothCharacteristic> candidates,
    String stored,
  ) {
    final parts = stored.split('|');
    if (parts.length != 2) return null;
    final service = parts[0].toLowerCase();
    final charId = parts[1].toLowerCase();
    for (final chr in candidates) {
      final sameService = _uuid16(chr.serviceUuid.str) == service;
      final sameChar = _uuid16(chr.characteristicUuid.str) == charId;
      if (sameService && sameChar) return chr;
    }
    return null;
  }

  Future<void> loadLogDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final dir = prefs.getString(_logDirKey);
    if (dir != null && dir.isNotEmpty) {
      await setLogDirectory(dir, persist: false);
      return;
    }
    if (Platform.isMacOS) {
      await setLogDirectory(_defaultProjectLogDir, persist: true);
    }
  }

  Future<void> setLogDirectory(String path, {bool persist = true}) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      logDirectory = dir.path;
      logFilePath = _buildLogFilePath(dir.path);
      logJsonlPath = _buildJsonlPath(dir.path);
      logToFileEnabled = true;
      if (persist) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_logDirKey, dir.path);
      }
      await _appendLogToFile(
        '--- log start ${DateTime.now().toIso8601String()} ---',
      );
      await _appendJsonlLog({
        'event': 'log_start',
        'ts': DateTime.now().toIso8601String(),
      });
      notifyListeners();
    } catch (e) {
      lastError = 'Log directory error: $e';
      notifyListeners();
    }
  }

  Future<void> rotateLogFile() async {
    final dir = logDirectory;
    if (dir == null) return;
    logFilePath = _buildLogFilePath(dir);
    logJsonlPath = _buildJsonlPath(dir);
    await _appendLogToFile(
      '--- log start ${DateTime.now().toIso8601String()} ---',
    );
    await _appendJsonlLog({
      'event': 'log_start',
      'ts': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  Future<void> quickStart() async {
    if (connectionState != BluetoothConnectionState.connected) {
      lastError = 'Not connected.';
      notifyListeners();
      return;
    }
    _autoSelectPreferredIfNeeded();
    await subscribeRx();
    await sendAuthPassword(authPassword);
    await sendStartupTelemetryKick();
    startKeepalive();
    startTelemetryPolling();
  }

  Future<void> subscribeRx() async {
    lastError = null;
    final chr = rxChar;
    if (chr == null) {
      lastError = 'Select an RX characteristic first.';
      notifyListeners();
      return;
    }
    try {
      await chr.setNotifyValue(true);
      _notifySub?.cancel();
      _notifyLastValueSub?.cancel();
      _notifySub = chr.onValueReceived.listen((value) {
        addLogBytes('RX', value, characteristic: chr);
      });
      _notifyLastValueSub = chr.lastValueStream.listen((value) {
        addLogBytes('RX', value, characteristic: chr);
      });
      isSubscribed = true;
      await _appendJsonlLog({
        'event': 'rx_subscribe',
        'ts': DateTime.now().toIso8601String(),
        'characteristic_uuid': chr.characteristicUuid.str,
      });
      notifyListeners();
    } catch (e) {
      lastError = 'Subscribe failed: $e';
      notifyListeners();
    }
  }

  Future<void> unsubscribeRx() async {
    lastError = null;
    final chr = rxChar;
    if (chr == null) return;
    try {
      await chr.setNotifyValue(false);
      _notifySub?.cancel();
      _notifySub = null;
      _notifyLastValueSub?.cancel();
      _notifyLastValueSub = null;
      isSubscribed = false;
      notifyListeners();
    } catch (e) {
      lastError = 'Unsubscribe failed: $e';
      notifyListeners();
    }
  }

  Future<bool> sendHex(
    String hex, {
    bool preferWithoutResponse = false,
    String? note,
  }) async {
    final bytes = hexToBytes(hex);
    if (bytes == null) {
      lastError = 'Invalid hex.';
      notifyListeners();
      return false;
    }
    return sendBytes(
      bytes,
      preferWithoutResponse: preferWithoutResponse,
      note: note,
    );
  }

  Future<bool> sendBytes(
    List<int> bytes, {
    bool preferWithoutResponse = false,
    BluetoothCharacteristic? characteristic,
    String? note,
  }) async {
    lastError = null;
    final chr = characteristic ?? txChar;
    if (chr == null) {
      lastError = 'Select a TX characteristic first.';
      notifyListeners();
      return false;
    }
    if (connectionState != BluetoothConnectionState.connected) {
      lastError = 'Not connected.';
      notifyListeners();
      return false;
    }

    try {
      final withoutResponse =
          preferWithoutResponse && chr.properties.writeWithoutResponse;
      await chr.write(bytes, withoutResponse: withoutResponse);
      addLogBytes('TX', bytes, characteristic: chr, note: note);
      return true;
    } catch (e) {
      lastError = 'Write failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<CommandAckState> waitForCommandAck({
    required int cmdId,
    DateTime? after,
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final state = _latestAckStateForCommand(cmdId, after: after);
      if (state != null) return state;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    final state = _latestAckStateForCommand(cmdId, after: after);
    return state ?? CommandAckState.timeout;
  }

  CommandAckState? _latestAckStateForCommand(int cmdId, {DateTime? after}) {
    for (final entry in logs) {
      if (entry.direction != 'RX') continue;
      if (after != null && !entry.timestamp.isAfter(after)) {
        continue;
      }
      final decoded = entry.decoded;
      if (decoded['frame_type'] != '0x03_ack') continue;
      if (decoded['checksum_ok'] != true) continue;
      final ackCmd = decoded['cmd_id'];
      if (ackCmd is! int || ackCmd != cmdId) continue;
      final ackOk = decoded['ack_ok'] == true;
      return ackOk ? CommandAckState.acknowledged : CommandAckState.rejected;
    }
    return null;
  }

  void startKeepalive() {
    if (keepaliveEnabled) return;
    keepaliveEnabled = true;
    _keepaliveTimer?.cancel();
    final intervalMs = (keepaliveSeconds * 1000).clamp(200, 10000).toInt();
    _keepaliveTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      sendHex('020606', preferWithoutResponse: true);
    });
    notifyListeners();
  }

  Future<void> sendStartupTelemetryKick() async {
    // Observed session kick frames from captures; used to encourage telemetry flow.
    const frames = ['020101', '020404', '020505'];
    for (final frame in frames) {
      await sendHex(frame, preferWithoutResponse: true, note: 'startup:$frame');
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  Future<void> sendAuthPassword(String password) async {
    final chunks = buildPasswordAuthChunks(password, maxChunkBytes: 20);
    for (var i = 0; i < chunks.length; i++) {
      await sendBytes(
        chunks[i],
        preferWithoutResponse: true,
        note: 'auth:${i + 1}/${chunks.length}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  static List<List<int>> buildPasswordAuthChunks(
    String password, {
    int maxChunkBytes = 20,
  }) {
    final normalized = password.trim();
    final digest = md5
        .convert(utf8.encode(normalized))
        .toString()
        .toUpperCase();
    final data = <int>[...digest.codeUnits, 0x00];
    const cmdId = 0x02;
    final checksum = (cmdId + data.fold<int>(0, (sum, b) => sum + b)) & 0xFF;
    final frame = <int>[data.length + 2, cmdId, ...data, checksum];

    if (maxChunkBytes <= 0 || frame.length <= maxChunkBytes) {
      return [frame];
    }

    final chunks = <List<int>>[];
    for (var i = 0; i < frame.length; i += maxChunkBytes) {
      final end = math.min(i + maxChunkBytes, frame.length);
      chunks.add(frame.sublist(i, end));
    }
    return chunks;
  }

  void startTelemetryPolling() {
    if (!telemetryPollingEnabled) return;
    _telemetryPollTimer?.cancel();
    final intervalMs = (telemetryPollSeconds * 1000).clamp(500, 10000).toInt();
    _telemetryPollTimer = Timer.periodic(Duration(milliseconds: intervalMs), (
      _,
    ) async {
      if (connectionState != BluetoothConnectionState.connected) return;
      await sendHex('020101', preferWithoutResponse: true, note: 'poll:020101');
      await sendHex('020404', preferWithoutResponse: true, note: 'poll:020404');
      await sendHex('020505', preferWithoutResponse: true, note: 'poll:020505');
    });
    notifyListeners();
  }

  void stopTelemetryPolling() {
    _telemetryPollTimer?.cancel();
    _telemetryPollTimer = null;
    notifyListeners();
  }

  void stopKeepalive() {
    keepaliveEnabled = false;
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    stopTelemetryPolling();
    notifyListeners();
  }

  void setKeepaliveSeconds(double value) {
    keepaliveSeconds = value;
    if (keepaliveEnabled) {
      stopKeepalive();
      startKeepalive();
    }
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  void addLogBytes(
    String direction,
    List<int> bytes, {
    BluetoothCharacteristic? characteristic,
    String? note,
  }) {
    final hex = bytesToHex(bytes);
    if (direction == 'RX') {
      final stamp = DateTime.now();
      if (_recentRxHex == hex && _recentRxStamp != null) {
        final deltaMs = stamp.difference(_recentRxStamp!).inMilliseconds;
        if (deltaMs >= 0 && deltaMs < 25) {
          return;
        }
      }
      _recentRxHex = hex;
      _recentRxStamp = stamp;
    }
    final decoded = decodePayload(bytes);
    if (direction == 'RX') {
      lastRxAt = DateTime.now();
    }
    logs.insert(
      0,
      BleLogEntry(
        timestamp: DateTime.now(),
        direction: direction,
        hex: hex,
        decoded: decoded,
        note: note,
      ),
    );
    if (logs.length > 300) {
      logs.removeRange(300, logs.length);
    }

    final line =
        '${DateTime.now().toIso8601String()} [$direction] $hex${note == null ? "" : " $note"}';
    unawaited(_appendLogToFile(line));

    final jsonLine = <String, dynamic>{
      'ts': DateTime.now().toIso8601String(),
      'direction': direction,
      'payload_hex': hex,
      'service_uuid': characteristic?.serviceUuid.str,
      'characteristic_uuid': characteristic?.characteristicUuid.str,
      'decoded': decoded,
      'note': note,
    };
    unawaited(_appendJsonlLog(jsonLine));
    notifyListeners();
  }

  String _buildLogFilePath(String dir) {
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return '$dir/ble_log_$stamp.txt';
  }

  String _buildJsonlPath(String dir) {
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return '$dir/ble_events_$stamp.jsonl';
  }

  Future<void> _appendLogToFile(String line) async {
    if (!logToFileEnabled || logFilePath == null) return;
    try {
      final file = File(logFilePath!);
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Avoid spamming UI with file write errors.
    }
  }

  Future<void> _appendJsonlLog(Map<String, dynamic> event) async {
    if (!logToFileEnabled || logJsonlPath == null) return;
    try {
      final file = File(logJsonlPath!);
      final line = jsonEncode(event);
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Avoid spamming UI with file write errors.
    }
  }
}
