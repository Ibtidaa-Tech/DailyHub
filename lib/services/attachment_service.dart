import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Photo attachments — receipts on expenses, images on notes.
///
/// Files go to Firebase Storage under attachments/{uid}/..., and the record
/// stores only the download URL. They are deliberately NOT base64'd into the
/// Realtime Database: RTDB has a 10MB node ceiling and a photo would blow
/// past the practical limit long before that, slowing every read of the
/// collection.
///
/// Note the separation from the vault: the vault is device-only precisely
/// because it holds secrets. Attachments are ordinary content and sync
/// normally, so a receipt is on your phone and the web build alike.
class AttachmentService {
  AttachmentService._();
  static final AttachmentService instance = AttachmentService._();

  final _picker = ImagePicker();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Picks from camera or gallery. Returns null if the user cancelled.
  /// Images are downscaled and recompressed before upload — a modern phone
  /// photo is 3-8MB, which is wasteful for a receipt and slow on mobile data.
  Future<XFile?> pick({required bool fromCamera}) async {
    try {
      return await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 75,
      );
    } catch (e) {
      debugPrint('Image pick failed: $e');
      return null;
    }
  }

  /// Uploads and returns the download URL.
  Future<String?> upload(XFile file, String folder) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final name =
          '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final ref =
          FirebaseStorage.instance.ref('attachments/$uid/$folder/$name');

      // Web has no File handle, so bytes are used there.
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        await ref.putData(
            bytes, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await ref.putFile(File(file.path));
      }
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Upload failed: $e');
      return null;
    }
  }

  /// Pick and upload in one step.
  Future<String?> pickAndUpload({
    required bool fromCamera,
    required String folder,
  }) async {
    final file = await pick(fromCamera: fromCamera);
    if (file == null) return null;
    return upload(file, folder);
  }

  /// Removes a previously uploaded file. Failure is non-fatal — the record
  /// reference is dropped either way, so a stale storage object is the worst
  /// case rather than a broken UI.
  Future<void> delete(String url) async {
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (e) {
      debugPrint('Attachment delete failed: $e');
    }
  }
}
