import 'package:flutter/material.dart';

import '../services/attachment_service.dart';

/// Add-and-preview strip for photo attachments. Drop into any form; it
/// hands back the updated URL list via [onChanged].
class AttachmentPicker extends StatefulWidget {
  final List<String> urls;
  final String folder;
  final ValueChanged<List<String>> onChanged;
  final String label;

  const AttachmentPicker({
    super.key,
    required this.urls,
    required this.folder,
    required this.onChanged,
    this.label = 'Photos',
  });

  @override
  State<AttachmentPicker> createState() => _AttachmentPickerState();
}

class _AttachmentPickerState extends State<AttachmentPicker> {
  bool _busy = false;

  Future<void> _add(bool fromCamera) async {
    setState(() => _busy = true);
    final url = await AttachmentService.instance
        .pickAndUpload(fromCamera: fromCamera, folder: widget.folder);
    if (!mounted) return;
    setState(() => _busy = false);
    if (url == null) return;
    widget.onChanged([...widget.urls, url]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_library_outlined,
                size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Text(widget.label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            if (_busy)
              const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              IconButton(
                tooltip: 'Take photo',
                icon: const Icon(Icons.photo_camera_outlined, size: 20),
                onPressed: () => _add(true),
              ),
              IconButton(
                tooltip: 'Choose from gallery',
                icon: const Icon(Icons.image_outlined, size: 20),
                onPressed: () => _add(false),
              ),
            ],
          ],
        ),
        if (widget.urls.isNotEmpty)
          SizedBox(
            height: 84,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.urls.length,
              itemBuilder: (context, i) {
                final url = widget.urls[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: () => _view(url),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            url,
                            height: 80,
                            width: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 80,
                              width: 80,
                              color: Colors.grey.shade300,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                    ? child
                                    : Container(
                                        height: 80,
                                        width: 80,
                                        color: Colors.grey.shade200,
                                        child: const Center(
                                          child: SizedBox(
                                            height: 18,
                                            width: 18,
                                            child:
                                                CircularProgressIndicator(
                                                    strokeWidth: 2),
                                          ),
                                        ),
                                      ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () async {
                            final updated = [...widget.urls]..remove(url);
                            widget.onChanged(updated);
                            await AttachmentService.instance.delete(url);
                          },
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _view(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(url),
              ),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white, size: 18),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }
}
