import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../ui/brand.dart';
import '../../ui/kit.dart';

/// Sign in / create account. Email + password or Google.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _auth = AuthService();
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _signUp = false;
  bool _hide = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  String _msg(Object e) {
    if (e is FirebaseAuthException) {
      final key = switch (e.code) {
        'invalid-email' => 'auth_err_email',
        'user-not-found' || 'wrong-password' || 'invalid-credential' || 'INVALID_LOGIN_CREDENTIALS' => 'auth_err_wrong',
        'email-already-in-use' => 'auth_err_in_use',
        'weak-password' => 'auth_err_weak',
        'network-request-failed' => 'auth_err_network',
        'too-many-requests' => 'auth_err_too_many',
        'user-disabled' => 'auth_err_disabled',
        'popup-closed-by-user' || 'cancelled-popup-request' => '',
        _ => 'auth_err_generic',
      };
      return key.isEmpty ? '' : context.t(key);
    }
    return context.t('auth_err_generic');
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_signUp) {
        await _auth.signUp(_email.text, _pass.text);
      } else {
        await _auth.signIn(_email.text, _pass.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        final m = _msg(e);
        setState(() => _error = m.isEmpty ? null : m);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final c = TextEditingController(text: _email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('reset_password')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ctx.t('reset_password_msg'), style: ctx.tt.bodyMedium),
          const SizedBox(height: 14),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: ctx.t('email'), prefixIcon: const Icon(Icons.mail_outline_rounded)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(ctx.t('send_link'))),
        ],
      ),
    );
    // Dispose after the dialog's exit animation, not while its TextField still uses it.
    WidgetsBinding.instance.addPostFrameCallback((_) => Future<void>.delayed(const Duration(milliseconds: 400), c.dispose));
    if (email == null || email.isEmpty || !mounted) return;
    try {
      await _auth.sendPasswordReset(email);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.mark_email_read_rounded, color: ctx.cs.primary, size: 36),
          title: Text(ctx.t('check_inbox')),
          content: Text(ctx.tr('reset_sent', {'email': email})),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.t('ok')))],
        ),
      );
    } catch (e) {
      if (mounted) showToast(context, _msg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final tk = context.tokens;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = _buildForm(context);
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          if (wide)
            Row(children: [
              const Expanded(child: _BrandPanel()),
              Expanded(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(32), child: form))),
            ])
          else
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                child: Column(children: [
                  const BrandMark(size: 68),
                  const SizedBox(height: 14),
                  Text('DailyHub', style: context.tt.headlineMedium),
                  const SizedBox(height: 4),
                  Text(context.t('tagline'), style: context.tt.bodyMedium?.copyWith(color: tk.textMuted), textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  form,
                ]),
              ),
            ),
          Positioned(
            top: 4,
            right: 8,
            child: TextButton.icon(
              icon: const Icon(Icons.translate_rounded, size: 18),
              label: Text(s.lang == 'hi' ? 'English' : 'हिन्दी'),
              onPressed: () => s.setLang(s.lang == 'hi' ? 'en' : 'hi'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final tk = context.tokens;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PillTabs<bool>(
            items: [(false, context.t('sign_in')), (true, context.t('create_account'))],
            value: _signUp,
            expand: true,
            onChanged: (v) => setState(() {
              _signUp = v;
              _error = null;
            }),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _passFocus.requestFocus(),
            decoration: InputDecoration(labelText: context.t('email'), prefixIcon: const Icon(Icons.mail_outline_rounded)),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return context.t('enter_email');
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) return context.t('auth_err_email');
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pass,
            focusNode: _passFocus,
            obscureText: _hide,
            autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: context.t('password'),
              helperText: _signUp ? context.t('password_hint') : null,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: context.t(_hide ? 'show' : 'hide'),
                icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
            validator: (v) {
              if ((v ?? '').isEmpty) return context.t('enter_password');
              if (_signUp && v!.length < 6) return context.t('auth_err_weak');
              return null;
            },
          ),
          if (!_signUp)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _busy ? null : _forgot, child: Text(context.t('forgot_password'))),
            )
          else
            const SizedBox(height: 16),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: tk.tint(tk.danger), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.error_outline_rounded, color: tk.danger, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: TextStyle(color: tk.danger))),
              ]),
            ),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(context.t(_signUp ? 'create_account' : 'sign_in'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Divider(color: tk.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(context.t('or'), style: context.tt.bodySmall),
            ),
            Expanded(child: Divider(color: tk.border)),
          ]),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: _busy ? null : _google,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const _GoogleG(),
                const SizedBox(width: 10),
                Text(context.t('continue_google'), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 22),
          Text(context.t('auth_privacy'), style: context.tt.bodySmall, textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, Color.lerp(cs.primary, const Color(0xFF7C3AED), 0.55)!],
        ),
      ),
      padding: const EdgeInsets.all(48),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(26)),
          child: const BrandMark(size: 72),
        ),
        const SizedBox(height: 28),
        Text('DailyHub', style: context.tt.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(context.t('tagline'), style: context.tt.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
        const SizedBox(height: 32),
        for (final k in ['ob_point_plan', 'ob_point_money', 'ob_point_habits'])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(context.t(k), style: context.tt.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.92))),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Four-colour Google "G" drawn with arcs, no asset needed.
class _GoogleG extends StatelessWidget {
  const _GoogleG();
  @override
  Widget build(BuildContext context) => const SizedBox(width: 20, height: 20, child: CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  const _GPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final stroke = w * 0.2;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, w - stroke, w - stroke);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const deg = 3.14159265 / 180;
    canvas.drawArc(rect, -40 * deg, -95 * deg, false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, -135 * deg, -90 * deg, false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 135 * deg, -95 * deg, false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, 40 * deg, -80 * deg, false, p(const Color(0xFF4285F4)));
    canvas.drawRect(Rect.fromLTWH(w / 2, w / 2 - stroke / 2, w / 2 - stroke / 4, stroke), Paint()..color = const Color(0xFF4285F4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
