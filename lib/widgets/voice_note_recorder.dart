import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../services/voice_service.dart';

/// Record-and-play strip for voice notes. Hands the updated URL list back
/// via [onChanged], same contract as AttachmentPicker.
class VoiceNoteRecorder extends StatefulWidget {
  final List<String> urls;
  final ValueChanged<List<String>> onChanged;

  const VoiceNoteRecorder({
    super.key,
    required this.urls,
    required this.onChanged,
  });

  @override
  State<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends State<VoiceNoteRecorder> {
  final _voice = VoiceService.instance;
  bool _recording = false;
  bool _busy = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  String? _playingUrl;
  StreamSubscription<PlayerState>? _playerSub;

  @override
  void dispose() {
    _ticker?.cancel();
    _playerSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      _ticker?.cancel();
      setState(() {
        _recording = false;
        _busy = true;
      });
      final url = await _voice.stopAndUpload();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _elapsed = Duration.zero;
      });
      if (url != null) widget.onChanged([...widget.urls, url]);
      return;
    }

    final ok = await _voice.hasPermission();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Microphone permission is needed to record')));
      }
      return;
    }
    final started = await _voice.start();
    if (!started || !mounted) return;
    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });
  }

  Future<void> _togglePlay(String url) async {
    if (_playingUrl == url) {
      await _voice.pausePlayback();
      if (!mounted) return;
      setState(() => _playingUrl = null);
      return;
    }
    await _voice.play(url);
    if (!mounted) return;
    setState(() => _playingUrl = url);
    _playerSub ??= _voice.playerState.listen((s) {
      if (s == PlayerState.completed && mounted) {
        setState(() => _playingUrl = null);
      }
    });
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.mic_none, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            const Text('Voice notes',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            if (_busy)
              const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else if (_voice.canRecord)
              Row(
                children: [
                  if (_recording)
                    Text(_fmt(_elapsed),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE74C3C))),
                  IconButton(
                    tooltip: _recording ? 'Stop and save' : 'Record',
                    icon: Icon(_recording ? Icons.stop_circle : Icons.mic,
                        color: _recording
                            ? const Color(0xFFE74C3C)
                            : const Color(0xFF667EEA)),
                    onPressed: _toggleRecord,
                  ),
                ],
              )
            else
              Text('Recording not available on web',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
        ...widget.urls.map((url) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: IconButton(
                icon: Icon(_playingUrl == url
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill),
                color: const Color(0xFF667EEA),
                onPressed: () => _togglePlay(url),
              ),
              title: Text(
                  'Voice note ${widget.urls.indexOf(url) + 1}',
                  style: const TextStyle(fontSize: 14)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  final updated = [...widget.urls]..remove(url);
                  widget.onChanged(updated);
                  await _voice.deleteRemote(url);
                },
              ),
            )),
      ],
    );
  }
}
