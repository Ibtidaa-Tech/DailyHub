import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../ui/kit.dart';

/// Basic calculator with correct operator precedence.
///
/// Precedence is handled by a small shunting-yard evaluator rather than
/// left-to-right chaining, so 2 + 3 × 4 gives 14, not 20 — which is what
/// most simple phone calculators get wrong.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  /// Long enough for any realistic sum, short enough that the display and the
  /// evaluator never have to cope with pathological input.
  static const int _maxLength = 40;
  static const int _maxHistory = 6;

  String _expr = '';
  String _result = '';
  final List<(String, String)> _history = [];

  void _tap(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (key) {
        case 'C':
          _expr = '';
          _result = '';
        case '⌫':
          if (_expr.isNotEmpty) {
            _expr = _expr.substring(0, _expr.length - 1);
            _result = _preview();
          }
        case '=':
          final r = _evaluate(_expr);
          final shown = r == null ? null : _format(r);
          if (shown != null && shown != _expr) {
            _history.insert(0, (_expr, shown));
            if (_history.length > _maxHistory) _history.removeLast();
            _result = '';
            _expr = shown;
          }
        default:
          if (_expr.length >= _maxLength) return;
          _expr += key;
          _result = _preview();
      }
    });
  }

  /// Puts an earlier answer back into the expression.
  void _reuse(String value) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_expr.length + value.length > _maxLength) return;
      final last = _expr.isEmpty ? '' : _expr[_expr.length - 1];
      // Typing a number straight after another number would glue them
      // together, so start fresh instead.
      if (_expr.isEmpty || _isOp(last)) {
        _expr += value;
      } else {
        _expr = value;
      }
      _result = _preview();
    });
  }

  void _clearHistory() {
    final saved = List<(String, String)>.from(_history);
    setState(_history.clear);
    showUndo(context, context.t('calc_history_cleared'), () {
      if (!mounted) return;
      setState(() {
        _history
          ..clear()
          ..addAll(saved);
      });
    });
  }

  void _copy() {
    final text = _result.isNotEmpty ? _result : (_expr.isEmpty ? '0' : _expr);
    Clipboard.setData(ClipboardData(text: text));
    showToast(context, context.t('calc_copied'), icon: Icons.copy_rounded);
  }

  String _preview() {
    final r = _evaluate(_expr);
    if (r == null) return '';
    return _format(r) ?? '';
  }

  /// Renders a result, or null when it isn't a finite number we can show.
  static String? _format(double v) {
    if (v.isNaN || v.isInfinite) return null;
    if (v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toStringAsFixed(0);
    }
    if (v.abs() >= 1e15) return v.toStringAsExponential(6);
    return v
        .toStringAsFixed(6)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  /// Tokenise, convert to RPN (shunting-yard), then evaluate.
  static double? _evaluate(String input) {
    if (input.trim().isEmpty) return null;
    final expr = input.replaceAll('×', '*').replaceAll('÷', '/');

    final tokens = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (RegExp(r'[0-9.]').hasMatch(ch)) {
        buffer.write(ch);
      } else if ('+-*/%'.contains(ch)) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        } else if (ch == '-' && (tokens.isEmpty || _isOp(tokens.last))) {
          // Unary minus: treat as part of the number.
          buffer.write(ch);
          continue;
        } else {
          return null;
        }
        tokens.add(ch);
      } else {
        return null;
      }
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());
    if (tokens.isEmpty || _isOp(tokens.last)) return null;

    const precedence = {'+': 1, '-': 1, '*': 2, '/': 2, '%': 2};
    final output = <String>[];
    final ops = <String>[];
    for (final t in tokens) {
      if (_isOp(t)) {
        while (ops.isNotEmpty &&
            (precedence[ops.last] ?? 0) >= (precedence[t] ?? 0)) {
          output.add(ops.removeLast());
        }
        ops.add(t);
      } else {
        output.add(t);
      }
    }
    while (ops.isNotEmpty) {
      output.add(ops.removeLast());
    }

    final stack = <double>[];
    for (final t in output) {
      if (_isOp(t)) {
        if (stack.length < 2) return null;
        final b = stack.removeLast();
        final a = stack.removeLast();
        stack.add(switch (t) {
          '+' => a + b,
          '-' => a - b,
          '*' => a * b,
          '/' => b == 0 ? double.nan : a / b,
          '%' => b == 0 ? double.nan : a % b,
          _ => double.nan,
        });
      } else {
        final v = double.tryParse(t);
        if (v == null) return null;
        stack.add(v);
      }
    }
    if (stack.length != 1) return null;
    final out = stack.first;
    return out.isFinite ? out : null;
  }

  static bool _isOp(String t) => t.length == 1 && '+-*/%'.contains(t);

  @override
  Widget build(BuildContext context) {
    const keys = [
      ['C', '⌫', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '-'],
      ['1', '2', '3', '+'],
      ['00', '0', '.', '='],
    ];
    final tk = context.tokens;

    return Scaffold(
      appBar: simpleBar(context, context.t('tool_calc'), actions: [
        if (_history.isNotEmpty)
          IconButton(
            tooltip: context.t('calc_clear_history'),
            icon: const Icon(Icons.history_toggle_off_rounded),
            onPressed: _clearHistory,
          ),
        IconButton(
          tooltip: context.t('calc_copied'),
          icon: const Icon(Icons.copy_rounded),
          onPressed: _copy,
        ),
      ]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_history.isNotEmpty) _HistoryStrip(items: _history, onTap: _reuse),
                Expanded(child: _display(context)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    children: [
                      for (final row in keys)
                        Row(
                          children: [for (final k in row) Expanded(child: _key(context, k, tk))],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _display(BuildContext context) {
    final tk = context.tokens;
    return Container(
      width: double.infinity,
      alignment: Alignment.bottomRight,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _expr.isEmpty ? '0' : _expr,
              style: context.tt.displaySmall?.copyWith(
                fontSize: 42,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _result.isEmpty ? '' : '= $_result',
              style: context.tt.titleLarge?.copyWith(
                color: tk.textMuted,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _key(BuildContext context, String k, AppTokens tk) {
    final isOp = k.length == 1 && '÷×-+%'.contains(k);
    final isEquals = k == '=';
    final isClear = k == 'C' || k == '⌫';
    final Color bg = isEquals
        ? context.cs.primary
        : isOp
            ? tk.tint(context.cs.primary)
            : isClear
                ? tk.tint(tk.danger)
                : tk.subtle;
    final Color fg = isEquals
        ? context.cs.onPrimary
        : isOp
            ? context.cs.primary
            : isClear
                ? tk.danger
                : context.cs.onSurface;

    return Padding(
      padding: const EdgeInsets.all(5),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _tap(k),
          child: ConstrainedBox(
            // Comfortable thumb target on every phone, and never below the
            // 48dp minimum even when the keypad is squeezed.
            constraints: const BoxConstraints(minHeight: 56, minWidth: 48),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    k,
                    maxLines: 1,
                    style: context.tt.titleLarge?.copyWith(
                        fontSize: 23, fontWeight: FontWeight.w700, color: fg),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The last few answers, newest first. Tapping one drops it back into the sum.
class _HistoryStrip extends StatelessWidget {
  final List<(String, String)> items;
  final ValueChanged<String> onTap;
  const _HistoryStrip({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SectionTitle(context.t('calc_history'),
              padding: const EdgeInsets.fromLTRB(4, 8, 0, 4)),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final h in items)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: tk.subtle,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => onTap(h.$2),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                            child: Text(h.$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.tt.bodySmall?.copyWith(color: tk.textFaint)),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('= ${h.$2}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.tt.labelMedium),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
