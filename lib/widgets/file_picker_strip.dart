import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/file_service.dart';

/// Add-and-list strip for file attachments (PDFs, tickets, documents).
/// Entries are stored as {url, name} maps so the original filename survives.
class FilePickerStrip extends StatefulWidget {
  final List<Map<String, dynamic>> files;
  final String folder;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final String label;

  const FilePickerStrip({
    super.key,
    required this.files,
    required this.folder,
    required this.onChanged,
    this.label = 'Files',
  });

  @override
  State<FilePickerStrip> createState() => _FilePickerStripState();
}

class _FilePickerStripState extends State<FilePickerStrip> {
  bool _busy = false;

  Future<void> _add() async {
    setState(() => _busy = true);
    try {
      final result =
          await FileService.instance.pickAndUpload(widget.folder);
      if (!mounted) return;
      setState(() => _busy = false);
      if (result == null) return;
      widget.onChanged([
        ...widget.files,
        {'url': result.url, 'name': result.name}
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', ''))));
    }
  }

  static IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (n.endsWith('.doc') || n.endsWith('.docx')) {
      return Icons.description_outlined;
    }
    if (n.endsWith('.xls') || n.endsWith('.xlsx') || n.endsWith('.csv')) {
      return Icons.table_chart_outlined;
    }
    if (n.endsWith('.zip')) return Icons.folder_zip_outlined;
    if (n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png')) {
      return Icons.image_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.attach_file, size: 18, color: Colors.grey),
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
            else
              IconButton(
                tooltip: 'Attach a file',
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: _add,
              ),
          ],
        ),
        ...widget.files.map((f) {
          final name = (f['name'] ?? 'File').toString();
          final url = (f['url'] ?? '').toString();
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(_iconFor(name),
                size: 22, color: const Color(0xFF667EEA)),
            title: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14)),
            onTap: () async {
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () async {
                final updated = [...widget.files]..remove(f);
                widget.onChanged(updated);
                await FileService.instance.delete(url);
              },
            ),
          );
        }),
      ],
    );
  }
}
