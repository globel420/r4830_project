import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/att_event.dart';

class ReplayController extends ChangeNotifier {
  List<AttEvent> _events = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  double _speed = 1.0;
  int _invalidLines = 0;
  int _totalLines = 0;
  String? _capturePath;
  int? _firstTs;
  Timer? _timer;

  List<AttEvent> get events => _events;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  double get speed => _speed;
  int get invalidLines => _invalidLines;
  int get totalLines => _totalLines;
  String? get capturePath => _capturePath;
  int? get firstTs => _firstTs;

  Future<void> loadCapture(String jsonlPath) async {
    stop();
    _capturePath = jsonlPath;
    _events = [];
    _currentIndex = -1;
    _invalidLines = 0;
    _totalLines = 0;
    _firstTs = null;

    final file = File(jsonlPath);
    if (!await file.exists()) {
      notifyListeners();
      return;
    }

    final lines = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    var index = 0;
    await for (final line in lines) {
      _totalLines++;
      if (line.trim().isEmpty) {
        _invalidLines++;
        continue;
      }

      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) {
          _invalidLines++;
          continue;
        }
        final event = AttEvent.fromJson(decoded, index);
        if (event == null) {
          _invalidLines++;
          continue;
        }
        _events.add(event);
        index++;
      } catch (_) {
        _invalidLines++;
      }
    }

    if (_events.isNotEmpty) {
      _firstTs = _events.first.ts;
    }

    notifyListeners();
  }

  void play() {
    if (_events.isEmpty) return;
    if (_isPlaying) return;
    _isPlaying = true;
    if (_currentIndex < 0) {
      _currentIndex = 0;
      notifyListeners();
    }
    _scheduleNext();
  }

  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void stop() {
    _isPlaying = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void reset() {
    pause();
    _currentIndex = -1;
    notifyListeners();
  }

  void step() {
    if (_events.isEmpty) return;
    pause();
    if (_currentIndex < _events.length - 1) {
      _currentIndex++;
      notifyListeners();
    }
  }

  void setSpeed(double speed) {
    if (_speed == speed) return;
    _speed = speed;
    if (_isPlaying) {
      _timer?.cancel();
      _timer = null;
      _scheduleNext();
    }
    notifyListeners();
  }

  bool isTelemetry(AttEvent event) {
    return event.type == 'ATT_HANDLE_VALUE_NTF' && event.handle == 3;
  }

  bool isCommand(AttEvent event) {
    return event.type == 'ATT_WRITE_CMD' && event.handle == 6;
  }

  List<AttEvent> filteredEvents({required bool telemetry, bool playedOnly = true}) {
    return _events.where((event) {
      final matches = telemetry ? isTelemetry(event) : isCommand(event);
      if (!matches) return false;
      if (!playedOnly) return true;
      return event.index <= _currentIndex;
    }).toList(growable: false);
  }

  int playedCount({required bool telemetry}) {
    var count = 0;
    for (final event in _events) {
      if (event.index > _currentIndex) break;
      if (telemetry && isTelemetry(event)) count++;
      if (!telemetry && isCommand(event)) count++;
    }
    return count;
  }

  void _scheduleNext() {
    if (!_isPlaying) return;
    if (_currentIndex >= _events.length - 1) {
      _isPlaying = false;
      notifyListeners();
      return;
    }

    final current = _events[_currentIndex];
    final next = _events[_currentIndex + 1];
    var deltaTicks = next.ts - current.ts;
    if (deltaTicks < 0) deltaTicks = 0;

    final scaled = (deltaTicks / _speed).round();
    final delay = Duration(microseconds: scaled);

    _timer = Timer(delay, () {
      if (!_isPlaying) return;
      _currentIndex++;
      notifyListeners();
      _scheduleNext();
    });
  }
}
