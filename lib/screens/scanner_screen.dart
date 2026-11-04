import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/localization.dart';
import '../core/theme.dart';
import '../services/db_service.dart';
import '../ui/kit.dart';

/// QR and barcode scanner. What it offers after a scan depends on what the code
/// contained — a link can be opened or bookmarked, plain text saved as a note.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;
  bool _torch = false;

  @override
  void dispose() {
    // The camera controller belongs to this State, so it is released here —
    // before super.dispose(), while the platform view is still attached.
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final codes = capture.barcodes;
    final raw = codes.isEmpty ? null : codes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _handled = true);
    _showResult(raw);
  }

  static bool _looksLikeUrl(String s) {
    final t = s.trim().toLowerCase();
    return t.startsWith('http://') || t.startsWith('https://') || t.startsWith('www.');
  }

  static Uri? _asUri(String value) {
    var u = value.trim();
    if (!u.startsWith('http')) u = 'https://$u';
    return Uri.tryParse(u);
  }

  Future<void> _showResult(String value) async {
    final isUrl = _looksLikeUrl(value);
    // A snackbar would sit behind the sheet, so the copy button confirms itself
    // instead of relying on a toast nobody can see.
    var copied = false;

    await showAppSheet<void>(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        final tk = ctx.tokens;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetHeader(ctx.t(isUrl ? 'scn_link_found' : 'scn_text_found')),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  IconBadge(
                    icon: isUrl ? Icons.link_rounded : Icons.text_snippet_outlined,
                    color: AppColors.mWork,
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tk.subtle,
                        borderRadius: BorderRadius.circular(Radii.m),
                      ),
                      // No maxLines: a scanner that hides part of what it read
                      // is worse than a sheet you have to scroll.
                      child: SelectableText(value, style: ctx.tt.bodyMedium),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  FilledButton.tonalIcon(
                    icon: Icon(
                      copied ? Icons.check_rounded : Icons.content_copy_rounded,
                      size: 18,
                      color: copied ? tk.success : null,
                    ),
                    label: Text(ctx.t(copied ? 'scn_copied' : 'copy')),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: value));
                      HapticFeedback.selectionClick();
                      set(() => copied = true);
                    },
                  ),
                  if (isUrl)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(ctx.t('scn_open_link')),
                      onPressed: () => _openScannedLink(ctx, value),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: Text(ctx.t('share')),
                    onPressed: () => Share.share(value),
                  ),
                  if (isUrl)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: Text(ctx.t('scn_save_bookmark')),
                      onPressed: () async {
                        await DbService.instance.add('bookmarks', {
                          'url': value.trim(),
                          'title': '',
                          'createdAt': DateTime.now().toIso8601String(),
                        });
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        showToast(context, context.t('scn_bookmarked'),
                            icon: Icons.bookmark_added_outlined);
                      },
                    )
                  else
                    OutlinedButton.icon(
                      icon: const Icon(Icons.note_add_outlined, size: 18),
                      label: Text(ctx.t('scn_save_note')),
                      onPressed: () async {
                        final title = ctx.t('scn_note_title');
                        await DbService.instance.add('notes', {
                          'title': title,
                          'body': value,
                          'color': 0,
                          'pinned': false,
                          'archived': false,
                          'tags': 'scanned',
                          'createdAt': DateTime.now().toIso8601String(),
                        });
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        showToast(context, context.t('scn_noted'),
                            icon: Icons.note_alt_outlined);
                      },
                    ),
                ]),
                const SizedBox(height: 14),
                TextButton.icon(
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: Text(ctx.t('scn_scan_again')),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      });
    });
    // Re-arm for the next scan.
    if (mounted) setState(() => _handled = false);
  }

  /// Opens a scanned link, closing the sheet first so a failure message is not
  /// hidden behind it.
  Future<void> _openScannedLink(BuildContext sheetContext, String value) async {
    final uri = _asUri(value);
    if (uri == null || !await canLaunchUrl(uri)) {
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      if (!mounted) return;
      showToast(context, context.t('scn_open_failed'), icon: Icons.link_off_rounded);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // A full-bleed camera can't live inside AppPage's scroll view, so this uses
    // the kit's plain bar for pushed screens instead.
    return Scaffold(
      appBar: simpleBar(context, context.t('m_scanner'), actions: [
        IconButton(
          tooltip: context.t('scn_torch'),
          isSelected: _torch,
          icon: const Icon(Icons.flashlight_on_outlined),
          selectedIcon: const Icon(Icons.flashlight_on_rounded),
          onPressed: () {
            setState(() => _torch = !_torch);
            _controller.toggleTorch();
          },
        ),
        IconButton(
          tooltip: context.t('scn_switch_camera'),
          icon: const Icon(Icons.cameraswitch_outlined),
          onPressed: () => _controller.switchCamera(),
        ),
        const SizedBox(width: 4),
      ]),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => Center(
              child: EmptyView(
                icon: Icons.no_photography_outlined,
                color: AppColors.mWork,
                title: context.t('scn_camera_off'),
                message: context.t('scn_camera_off_msg'),
              ),
            ),
          ),
          const _Viewfinder(),
          Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: SafeArea(
              top: false,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.t('scn_hint'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: context.tt.labelMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Four bright rounded brackets over a dimmed surround: it reads as "aim here"
/// without covering what the camera sees.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) {
    // `.clamp` is declared on num and returns num; SizedBox needs a double.
    final double side =
        (MediaQuery.sizeOf(context).shortestSide * 0.66).clamp(180.0, 300.0).toDouble();
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: side,
          height: side,
          child: CustomPaint(painter: _FramePainter(accent: context.cs.primary)),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  final Color accent;
  _FramePainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 22.0;
    const arm = 38.0;
    final rect = Offset.zero & size;

    // Dim everything outside the frame so the eye lands inside it.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect.inflate(2000)),
      Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(radius))),
    );
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.35));

    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;

    void bracket(Offset corner, double dx, double dy) {
      final path = Path()
        ..moveTo(corner.dx + dx * (radius + arm), corner.dy)
        ..lineTo(corner.dx + dx * radius, corner.dy)
        ..arcToPoint(
          Offset(corner.dx, corner.dy + dy * radius),
          radius: const Radius.circular(radius),
          // The arc has to curve towards the corner, which flips with the
          // quadrant the bracket sits in.
          clockwise: dx * dy < 0,
        )
        ..lineTo(corner.dx, corner.dy + dy * (radius + arm));
      canvas.drawPath(path, p);
    }

    bracket(Offset.zero, 1, 1);
    bracket(Offset(size.width, 0), -1, 1);
    bracket(Offset(0, size.height), 1, -1);
    bracket(Offset(size.width, size.height), -1, -1);

    // A soft accent line across the middle, so the frame doesn't feel dead.
    canvas.drawLine(
      Offset(radius, size.height / 2),
      Offset(size.width - radius, size.height / 2),
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.65),
    );
  }

  @override
  bool shouldRepaint(_FramePainter o) => o.accent != accent;
}
