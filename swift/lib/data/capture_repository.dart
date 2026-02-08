import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class CaptureInfo {
  CaptureInfo({
    required this.name,
    required this.directoryPath,
    required this.jsonlPath,
    required this.lineCount,
  });

  final String name;
  final String directoryPath;
  final String jsonlPath;
  final int? lineCount;
}

class CaptureRepository {
  static const _lastCaptureKey = 'last_capture_path';
  List<String> lastSearchPaths = [];
  String? lastWorkingDirectory;
  String? lastPwdEnv;
  List<String> lastErrors = [];

  Future<List<CaptureInfo>> listCaptures() async {
    lastErrors = [];
    final baseRoots = <String>{};
    final cwd = Directory.current.path;
    lastWorkingDirectory = cwd;
    baseRoots.addAll(_walkUp(cwd, maxDepth: 10));

    final pwd = Platform.environment['PWD'];
    if (pwd != null && pwd.isNotEmpty) {
      lastPwdEnv = pwd;
      baseRoots.addAll(_walkUp(pwd, maxDepth: 10));
    } else {
      lastPwdEnv = null;
    }

    const knownRepoRoot = '/Users/globel/r4830_project';
    if (await Directory(knownRepoRoot).exists()) {
      baseRoots.add(knownRepoRoot);
    }

    final candidates = <String>{};
    for (final root in baseRoots) {
      candidates.add(p.normalize(p.join(root, 'captures')));
      candidates.add(p.normalize(p.join(root, 'controller', 'captures')));
    }
    lastSearchPaths = candidates.toList()..sort();

    final results = <CaptureInfo>[];
    for (final root in candidates) {
      final dir = Directory(root);
      if (!await dir.exists()) {
        continue;
      }

      try {
        await for (final entry in dir.list(followLinks: false)) {
          if (entry is! Directory) continue;
          final name = p.basename(entry.path);
          if (!name.startsWith('cap_')) continue;

          final jsonlPath = p.join(entry.path, 'att_events.jsonl');
          if (!await File(jsonlPath).exists()) continue;

          final lineCount = await _tryCountLines(jsonlPath);
          results.add(CaptureInfo(
            name: name,
            directoryPath: entry.path,
            jsonlPath: jsonlPath,
            lineCount: lineCount,
          ));
        }
      } catch (e) {
        lastErrors.add('$root: $e');
      }
    }

    results.sort((a, b) => b.name.compareTo(a.name));
    return results;
  }

  Future<void> saveLastCapturePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCaptureKey, path);
  }

  Future<String?> loadLastCapturePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastCaptureKey);
  }

  Future<int?> _tryCountLines(String path) async {
    try {
      var count = 0;
      final stream = File(path)
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final _ in stream) {
        count++;
      }
      return count;
    } catch (_) {
      return null;
    }
  }

  Iterable<String> _walkUp(String start, {int maxDepth = 8}) sync* {
    var current = p.normalize(start);
    for (var i = 0; i < maxDepth; i++) {
      yield current;
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
  }
}
