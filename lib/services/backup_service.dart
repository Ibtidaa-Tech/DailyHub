import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import 'db_service.dart';

/// Full-account backup to a JSON file, and restore from one.
///
/// The backup contains everything under your account (tasks, money, notes,
/// habits…) but NOT the device-only vault, which never leaves the phone.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// Nodes that must not be restored blindly (sharing is two-sided).
  static const _skip = {'collaborators', 'sharedWithMe'};

  Future<Map<String, dynamic>> build() async {
    final data = await DbService.instance.exportAll();
    return {
      'app': 'DailyHub',
      'format': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': data,
    };
  }

  Future<void> exportAndShare() async {
    final json = const JsonEncoder.withIndent('  ').convert(await build());
    final bytes = Uint8List.fromList(utf8.encode(json));
    final name = 'dailyhub-backup-${dayKey(DateTime.now())}.json';
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: name, mimeType: 'application/json')],
      subject: 'DailyHub backup',
      fileNameOverrides: [name],
    );
  }

  /// Opens a file picker and returns the parsed backup, or null.
  Future<Map<String, dynamic>?> pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final file = res?.files.firstOrNull;
    final bytes = file?.bytes;
    if (bytes == null) return null;
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('Not a DailyHub backup');
    final map = Map<String, dynamic>.from(decoded);
    final data = map['data'] is Map ? Map<String, dynamic>.from(map['data']) : map;
    return data;
  }

  /// Item counts per collection, for the confirmation dialog.
  Map<String, int> summarize(Map<String, dynamic> data) {
    final out = <String, int>{};
    data.forEach((k, v) {
      if (_skip.contains(k) || v is! Map) return;
      if (k == 'profile' || k == 'prefs') return;
      out[k] = v.length;
    });
    return out;
  }

  /// Merges the backup into your account. Existing items with the same id
  /// are overwritten; nothing else is deleted.
  Future<int> restore(Map<String, dynamic> data) async {
    final paths = <String, dynamic>{};
    var count = 0;
    data.forEach((k, v) {
      if (_skip.contains(k)) return;
      if (k == 'profile' || k == 'prefs') {
        if (v is Map) {
          v.forEach((kk, vv) => paths['$k/$kk'] = vv);
        }
        return;
      }
      if (v is Map) {
        v.forEach((id, item) {
          paths['$k/$id'] = item;
          count++;
        });
      }
    });
    if (paths.isNotEmpty) await DbService.instance.updateRoot(paths);
    return count;
  }
}
