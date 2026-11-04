import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Voice notes: record on device, upload to Firebase Storage, play back
/// from the URL.
///
/// Recording is mobile-only. The `record` package does support web via
/// MediaRecorder, but the output container differs by browser and the
/// resulting files don't play back reliably across all of them — so rather
/// than ship something that works on Chrome and breaks on Safari, web gets
/// playback only.
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  String? _currentPath;

  bool get canRecord => !kIsWeb;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<bool> hasPermission() async {
    if (kIsWeb) return false;
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('Mic permission check failed: $e');
      return false;
    }
  }

  Future<bool> start() async {
    if (kIsWeb) return false;
    try {
      if (!await _recorder.hasPermission()) return false;
      final dir = await getTemporaryDirectory();
      _currentPath =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: _currentPath!,
      );
      return true;
    } catch (e) {
      debugPrint('Recording failed to start: $e');
      return false;
    }
  }

  /// Stops recording and uploads. Returns the download URL, or null.
  Future<String?> stopAndUpload() async {
    if (kIsWeb) return null;
    try {
      final path = await _recorder.stop();
      final file = File(path ?? _currentPath ?? '');
      if (!await file.exists()) return null;

      final uid = _uid;
      if (uid == null) return null;

      final name = file.uri.pathSegments.last;
      final ref =
          FirebaseStorage.instance.ref('attachments/$uid/voice/$name');
      await ref.putFile(file, SettableMetadata(contentType: 'audio/mp4'));
      final url = await ref.getDownloadURL();

      // The local temp copy has served its purpose.
      try {
        await file.delete();
      } catch (_) {}

      return url;
    } catch (e) {
      debugPrint('Recording upload failed: $e');
      return null;
    }
  }

  Future<void> cancel() async {
    if (kIsWeb) return;
    try {
      await _recorder.stop();
      final p = _currentPath;
      if (p != null) {
        final f = File(p);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  Future<bool> isRecording() async {
    if (kIsWeb) return false;
    try {
      return await _recorder.isRecording();
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------- playback

  Stream<PlayerState> get playerState => _player.onPlayerStateChanged;
  Stream<Duration> get position => _player.onPositionChanged;
  Stream<Duration> get duration => _player.onDurationChanged;

  Future<void> play(String url) async {
    await _player.stop();
    await _player.play(UrlSource(url));
  }

  Future<void> pausePlayback() => _player.pause();
  Future<void> stopPlayback() => _player.stop();

  Future<void> deleteRemote(String url) async {
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (e) {
      debugPrint('Voice note delete failed: $e');
    }
  }

  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}
