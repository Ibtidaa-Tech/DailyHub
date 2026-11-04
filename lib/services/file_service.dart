import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// File attachments — PDFs, tickets, documents. Same Storage layout as
/// photos, so one set of Storage rules covers everything.
class FileService {
  FileService._();
  static final FileService instance = FileService._();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Size ceiling. Firebase Storage allows far more, but a 50MB attachment
  /// on mobile data is a bad experience and quietly burns the free quota.
  static const int maxBytes = 15 * 1024 * 1024;

  /// Returns (url, filename) or null if cancelled / rejected.
  Future<({String url, String name})?> pickAndUpload(String folder) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv',
          'zip', 'jpg', 'jpeg', 'png',
        ],
        withData: kIsWeb, // web has no file path, only bytes
      );
      if (result == null || result.files.isEmpty) return null;
      final picked = result.files.first;

      if (picked.size > maxBytes) {
        throw Exception(
            'File is ${(picked.size / 1048576).toStringAsFixed(1)}MB — the limit is 15MB');
      }

      final ref = FirebaseStorage.instance.ref(
          'attachments/$uid/$folder/${DateTime.now().millisecondsSinceEpoch}_${picked.name}');

      if (kIsWeb) {
        final bytes = picked.bytes;
        if (bytes == null) return null;
        await ref.putData(bytes);
      } else {
        final path = picked.path;
        if (path == null) return null;
        await ref.putFile(File(path));
      }

      final url = await ref.getDownloadURL();
      return (url: url, name: picked.name);
    } catch (e) {
      debugPrint('File upload failed: $e');
      rethrow;
    }
  }

  Future<void> delete(String url) async {
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (e) {
      debugPrint('File delete failed: $e');
    }
  }
}
