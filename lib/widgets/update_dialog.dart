import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../services/update_service.dart';

/// Shows the "update available" dialog. Called once after login, and
/// on demand from Settings.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: const BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.system_update,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Update available')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version ${info.version} is ready to download.',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (info.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(info.notes.trim(),
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade700)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'The download opens in your browser. You may need to allow '
            'installing apps from unknown sources.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await UpdateService.instance.skipVersion(info.version);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Skip this version'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () async {
            final url = info.apkUrl ?? info.pageUrl;
            final uri = Uri.tryParse(url);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Download'),
        ),
      ],
    ),
  );
}
