import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../data/capture_repository.dart';
import 'session_viewer_screen.dart';

class CapturePickerScreen extends StatefulWidget {
  const CapturePickerScreen({super.key});

  @override
  State<CapturePickerScreen> createState() => _CapturePickerScreenState();
}

class _CapturePickerScreenState extends State<CapturePickerScreen> {
  final CaptureRepository _repository = CaptureRepository();
  late Future<List<CaptureInfo>> _capturesFuture;
  String? _lastCapturePath;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _capturesFuture = _repository.listCaptures();
    });
    final last = await _repository.loadLastCapturePath();
    if (mounted) {
      setState(() {
        _lastCapturePath = last;
      });
    }
  }

  void _openCapture(CaptureInfo capture) {
    _repository.saveLastCapturePath(capture.jsonlPath);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionViewerScreen(capture: capture),
      ),
    );
  }

  Future<void> _pickCaptureFile() async {
    const group = XTypeGroup(label: 'ATT events', extensions: ['jsonl']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;

    final path = file.path;
    final exists = await File(path).exists();
    if (!exists) {
      _showSnack('Selected file no longer exists.');
      return;
    }

    final capture = CaptureInfo(
      name: p.basename(p.dirname(path)),
      directoryPath: p.dirname(path),
      jsonlPath: path,
      lineCount: null,
    );
    _openCapture(capture);
  }

  Future<void> _pickCaptureFolder() async {
    final directory = await getDirectoryPath();
    if (directory == null) return;
    final jsonlPath = p.join(directory, 'att_events.jsonl');
    final exists = await File(jsonlPath).exists();
    if (!exists) {
      _showSnack('No att_events.jsonl found in that folder.');
      return;
    }
    final capture = CaptureInfo(
      name: p.basename(directory),
      directoryPath: directory,
      jsonlPath: jsonlPath,
      lineCount: null,
    );
    _openCapture(capture);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Picker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _pickCaptureFolder,
            tooltip: 'Open capture folder',
          ),
          IconButton(
            icon: const Icon(Icons.insert_drive_file),
            onPressed: _pickCaptureFile,
            tooltip: 'Open att_events.jsonl',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Rescan',
          ),
        ],
      ),
      body: FutureBuilder<List<CaptureInfo>>(
        future: _capturesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final captures = snapshot.data ?? [];
          if (captures.isEmpty) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No captures found. Check ../captures or ../controller/captures.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'If macOS sandbox blocks access, use the folder or file picker buttons in the top-right.',
                      ),
                      const SizedBox(height: 12),
                      Text('Working directory: ${_repository.lastWorkingDirectory ?? "unknown"}'),
                      Text('PWD env: ${_repository.lastPwdEnv ?? "unset"}'),
                      const SizedBox(height: 8),
                      if (_repository.lastErrors.isNotEmpty) ...[
                        const Text('Access errors:'),
                        const SizedBox(height: 6),
                        ..._repository.lastErrors.map(
                          (error) => Text(error, style: Theme.of(context).textTheme.bodySmall),
                        ),
                        const SizedBox(height: 8),
                      ],
                      const Text('Search paths tried:'),
                      const SizedBox(height: 6),
                      ..._repository.lastSearchPaths.map(
                        (path) => Text(path, style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: captures.length + (_lastCapturePath == null ? 0 : 1),
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (_lastCapturePath != null && index == 0) {
                final last = captures.firstWhere(
                  (c) => c.jsonlPath == _lastCapturePath,
                  orElse: () => captures.first,
                );
                return Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    title: Text('Last opened: ${last.name}'),
                    subtitle: Text(last.jsonlPath),
                    trailing: const Icon(Icons.play_arrow),
                    onTap: () => _openCapture(last),
                  ),
                );
              }

              final captureIndex = _lastCapturePath == null ? index : index - 1;
              final capture = captures[captureIndex];
              final lineCount = capture.lineCount == null
                  ? 'line count: TBD'
                  : 'line count: ${capture.lineCount}';

              return Card(
                child: ListTile(
                  title: Text(capture.name),
                  subtitle: Text('${capture.jsonlPath}\n$lineCount'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openCapture(capture),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
