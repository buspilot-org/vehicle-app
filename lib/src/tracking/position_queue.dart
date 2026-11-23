import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'position_record.dart';

/// First-in, first-out queue of positions waiting to be sent, kept in a file
/// so that nothing is lost while the phone is offline or the app restarts.
///
/// The file holds one JSON record per line. New positions are appended; sent
/// positions are removed by rewriting the file (written to a temporary file
/// first, then renamed, so a crash cannot leave a half-written queue).
///
/// Only one isolate (the tracking service) may own the queue file.
class FilePositionQueue {
  FilePositionQueue._(this._file, this.maxLength, this._items);

  /// Default cap: about 5.8 days of positions at one fix every 10 seconds.
  static const defaultMaxLength = 50000;

  final File _file;

  /// When the queue grows past this, the oldest positions are dropped.
  final int maxLength;

  final ListQueue<PositionRecord> _items;
  Future<void> _lock = Future.value();
  int _dropped = 0;

  /// Opens the queue stored in [file], creating it if needed. Lines that
  /// cannot be read (for example a line cut off by a crash) are skipped and
  /// the file is rewritten without them.
  static Future<FilePositionQueue> open(
    File file, {
    int maxLength = defaultMaxLength,
  }) async {
    if (maxLength < 1) throw ArgumentError.value(maxLength, 'maxLength');
    final items = ListQueue<PositionRecord>();
    var needsRewrite = false;
    if (await file.exists()) {
      final lines = await file.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          items.add(
            PositionRecord.fromJson(jsonDecode(line) as Map<String, Object?>),
          );
        } on FormatException {
          needsRewrite = true;
        } on TypeError {
          needsRewrite = true;
        }
      }
    } else {
      await file.parent.create(recursive: true);
    }
    final queue = FilePositionQueue._(file, maxLength, items);
    if (items.length > maxLength) {
      queue._dropOldest(items.length - maxLength);
      needsRewrite = true;
    }
    if (needsRewrite) await queue._rewrite();
    return queue;
  }

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  /// Number of positions dropped since opening because the queue was full.
  int get droppedCount => _dropped;

  /// The oldest [count] positions, without removing them.
  List<PositionRecord> peek(int count) => _items.take(count).toList();

  /// Appends [record] at the end of the queue.
  Future<void> add(PositionRecord record) => _synchronized(() async {
    _items.add(record);
    if (_items.length > maxLength) {
      // Drop 10 % at once so a full queue is not rewritten on every add.
      final excess = _items.length - maxLength;
      _dropOldest(excess + maxLength ~/ 10);
      await _rewrite();
    } else {
      await _file.writeAsString(
        '${jsonEncode(record.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
    }
  });

  /// Removes the oldest [count] positions.
  Future<void> removeFirst(int count) => _synchronized(() async {
    if (count <= 0) return;
    final n = count > _items.length ? _items.length : count;
    for (var i = 0; i < n; i++) {
      _items.removeFirst();
    }
    await _rewrite();
  });

  /// Removes [sent] (records obtained from [peek], in order) from the head of
  /// the queue. Records that are no longer at the head, because a full queue
  /// dropped them in the meantime, are skipped, so nothing unsent is removed.
  Future<void> removeSent(List<PositionRecord> sent) => _synchronized(() async {
    var changed = false;
    for (final record in sent) {
      if (_items.isNotEmpty && identical(_items.first, record)) {
        _items.removeFirst();
        changed = true;
      }
    }
    if (changed) await _rewrite();
  });

  void _dropOldest(int count) {
    final n = count > _items.length ? _items.length : count;
    for (var i = 0; i < n; i++) {
      _items.removeFirst();
    }
    _dropped += n;
  }

  Future<void> _rewrite() async {
    final tmp = File('${_file.path}.tmp');
    final sink = tmp.openWrite();
    for (final item in _items) {
      sink.writeln(jsonEncode(item.toJson()));
    }
    await sink.flush();
    await sink.close();
    await tmp.rename(_file.path);
  }

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }
}
