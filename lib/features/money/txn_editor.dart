import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../ui/kit.dart';
import '../../widgets/attachment_picker.dart';
import 'categories_screen.dart';
import 'money_ui.dart';

/// Opens the one-tap money entry sheet.
Future<void> openTxnEditor(
  BuildContext context, {
  Txn? txn,
  String type = TxnType.expense,
  double? amount,
  String? note,
  String? category,
}) {
  final money = context.read<MoneyStore>();
  final settings = context.read<AppSettings>();
  return showAppSheet(
    context,
    expand: true,
    builder: (ctx) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: money),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: _TxnSheet(txn: txn, type: txn?.type ?? type, amount: amount, note: note, category: category),
    ),
  );
}

/// Tiny safe calculator: + − × ÷ with normal precedence.
class Calc {
  static double? eval(String expr) {
    final e = expr.replaceAll('×', '*').replaceAll('÷', '/').replaceAll('−', '-');
    if (e.isEmpty) return null;
    final tokens = <String>[];
    var num = '';
    for (var i = 0; i < e.length; i++) {
      final ch = e[i];
      if ('0123456789.'.contains(ch)) {
        num += ch;
      } else if ('+-*/'.contains(ch)) {
        if (num.isNotEmpty) {
          tokens.add(num);
          num = '';
        } else if (tokens.isEmpty) {
          continue;
        } else {
          tokens.removeLast(); // replace a repeated operator
        }
        tokens.add(ch);
      }
    }
    if (num.isNotEmpty) tokens.add(num);
    if (tokens.isNotEmpty && '+-*/'.contains(tokens.last)) tokens.removeLast();
    if (tokens.isEmpty) return null;
    // First pass: * and /
    final pass = <String>[];
    var i = 0;
    while (i < tokens.length) {
      final tk = tokens[i];
      if ((tk == '*' || tk == '/') && pass.isNotEmpty && i + 1 < tokens.length) {
        final a = double.tryParse(pass.removeLast()) ?? 0;
        final b = double.tryParse(tokens[i + 1]) ?? 0;
        if (tk == '/' && b == 0) return null;
        pass.add('${tk == '*' ? a * b : a / b}');
        i += 2;
      } else {
        pass.add(tk);
        i++;
      }
    }
    var total = double.tryParse(pass.first) ?? 0;
    for (var j = 1; j + 1 < pass.length; j += 2) {
      final b = double.tryParse(pass[j + 1]) ?? 0;
      total = pass[j] == '+' ? total + b : total - b;
    }
    final r = (total * 100).roundToDouble() / 100;
    // Overflow (e.g. a long chain of ×) must never reach the UI or the DB.
    return r.isFinite ? r : null;
  }

  static bool hasOperator(String s) => s.contains(RegExp(r'[+\-×÷−]'));
}

class _TxnSheet extends StatefulWidget {
  final Txn? txn;
  final String type;
  final double? amount;
  final String? note;
  final String? category;
  const _TxnSheet({this.txn, required this.type, this.amount, this.note, this.category});
  @override
  State<_TxnSheet> createState() => _TxnSheetState();
}

class _TxnSheetState extends State<_TxnSheet> {
  late String _type = widget.type;
  String _expr = '';
  String _category = '';
  bool _catTouched = false;
  String _account = '';
  String _toAccount = '';
  DateTime _date = DateTime.now();
  final TextEditingController _note = TextEditingController();
  final FocusNode _noteFocus = FocusNode();
  List<String> _photos = [];
  int _splitN = 1;
  List<String> _splitNames = [];

  bool get _isNew => widget.txn == null;

  @override
  void initState() {
    super.initState();
    final m = context.read<MoneyStore>();
    final s = context.read<AppSettings>();
    final t = widget.txn;
    if (t != null) {
      _expr = _fmtNum(t.amount);
      _category = t.category;
      _catTouched = true;
      _account = t.account;
      _toAccount = t.toAccount;
      _date = t.day;
      _note.text = t.note;
      _photos = List.of(t.photos);
    } else {
      if (widget.amount != null) _expr = _fmtNum(widget.amount!);
      _note.text = widget.note ?? '';
      _category = widget.category ?? '';
      _catTouched = widget.category != null;
      final def = s.defaultAccount;
      _account = m.accountById(def) != null && !(m.accountById(def)!.archived) ? def : m.defaultAccountId;
    }
    if (_category.isEmpty) _category = m.guessCategory(_note.text, _kind);
    _note.addListener(_onNote);
    _noteFocus.addListener(() => setState(() {}));
  }

  String get _kind => _type == TxnType.income ? 'income' : 'expense';

  static String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  void _onNote() {
    if (_catTouched) return;
    final g = context.read<MoneyStore>().guessCategory(_note.text, _kind);
    if (g != _category) setState(() => _category = g);
  }

  @override
  void dispose() {
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// The number currently being typed (after the last operator).
  String get _lastNum {
    final parts = _expr.split(RegExp(r'[+−×÷]'));
    return parts.isEmpty ? '' : parts.last;
  }

  void _key(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '⌫') {
        if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
        return;
      }
      if ('+−×÷'.contains(k)) {
        if (_expr.isEmpty) return;
        final last = _expr[_expr.length - 1];
        if ('+−×÷'.contains(last)) {
          _expr = _expr.substring(0, _expr.length - 1) + k;
        } else {
          _expr += k;
        }
        return;
      }
      if (k == '.') {
        final lastNum = _lastNum;
        if (lastNum.contains('.')) return;
        _expr += lastNum.isEmpty ? '0.' : '.';
        return;
      }
      // Digit: cap to 2 decimals and a sane length.
      final lastNum = _lastNum;
      final dot = lastNum.indexOf('.');
      if (dot >= 0 && lastNum.length - dot > 2) return;
      if (lastNum.replaceAll('.', '').length >= 10) return;
      if (lastNum == '0' && k != '.') {
        _expr = _expr.substring(0, _expr.length - 1) + k;
        return;
      }
      _expr += k;
    });
  }

  double? get _amount => Calc.eval(_expr);

  void _save() {
    final amt = _amount;
    if (amt == null || amt <= 0) {
      HapticFeedback.heavyImpact();
      showToast(context, context.t('enter_amount'));
      return;
    }
    final m = context.read<MoneyStore>();
    if (_type == TxnType.transfer) {
      if (_account.isEmpty || _toAccount.isEmpty || _account == _toAccount) {
        showToast(context, context.t('pick_two_accounts'));
        return;
      }
    }
    final share = _splitN > 1 ? (amt / _splitN * 100).roundToDouble() / 100 : amt;
    final t = widget.txn ?? Txn();
    final saved = Txn(
      id: t.id,
      raw: t.raw,
      type: _type,
      amount: _type == TxnType.expense ? share : amt,
      category: _type == TxnType.transfer ? '' : _category,
      note: _note.text.trim(),
      date: dayKey(_date),
      time: _isNew ? hmOf(DateTime.now()) : t.time,
      account: _account,
      toAccount: _type == TxnType.transfer ? _toAccount : '',
      photos: _photos,
      split: _splitN > 1 ? {'total': amt, 'n': _splitN, 'people': _splitNames} : t.split,
      billId: t.billId,
      createdAt: t.createdAt,
    );
    final id = m.saveTxn(saved);
    if (_isNew && _splitN > 1 && _type == TxnType.expense) {
      for (var i = 0; i < _splitN - 1; i++) {
        final name = i < _splitNames.length && _splitNames[i].trim().isNotEmpty
            ? _splitNames[i].trim()
            : '${context.t('friend')} ${i + 1}';
        m.saveDebt(Debt(
          person: name,
          kind: 'lent',
          amount: share,
          note: _note.text.trim().isEmpty ? context.t('split_bill') : _note.text.trim(),
          date: dayKey(_date),
        ));
      }
    }
    if (_account.isNotEmpty) context.read<AppSettings>().setDefaultAccount(_account);
    final label = _type == TxnType.transfer
        ? context.t('transfer_saved')
        : '${context.t(_type == TxnType.income ? 'earned' : 'spent')} ${Money.format(saved.amount)} · ${categoryName(context, m.catById(_category))}';
    Navigator.pop(context);
    if (_isNew) {
      showUndo(context, label, () => m.deleteTxn(Txn(id: id)));
    } else {
      showToast(context, context.t('saved'), icon: Icons.check_circle_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final tk = context.tokens;
    final color = typeColor(context, _type);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final amt = _amount;

    return SafeArea(
      top: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(children: [
            Expanded(
              child: PillTabs<String>(
                items: [
                  (TxnType.expense, context.t('spent')),
                  (TxnType.income, context.t('earned')),
                  (TxnType.transfer, context.t('transfer')),
                ],
                value: _type,
                onChanged: (v) => setState(() {
                  _type = v;
                  if (!_catTouched || m.catById(_category)?.kind != _kind) {
                    _catTouched = false;
                    _category = m.guessCategory(_note.text, _kind);
                  }
                  if (v != TxnType.expense) _splitN = 1;
                }),
              ),
            ),
            if (!_isNew)
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: tk.danger),
                onPressed: () {
                  final t = widget.txn!;
                  final data = m.deleteTxn(t);
                  Navigator.pop(context);
                  showUndo(context, context.t('txn_deleted'), () => m.restore('txns', t.id, data));
                },
              ),
          ]),
        ),
        // Amount
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Column(children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: Calc.hasOperator(_expr) ? 1 : 0,
              child: Text(_expr, style: context.tt.bodyMedium?.copyWith(color: tk.textMuted)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _expr.isEmpty ? Money.format(0) : Money.format(amt ?? 0),
                style: context.tt.displaySmall?.copyWith(
                  color: _expr.isEmpty ? tk.textFaint : color,
                  fontSize: 44,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (_splitN > 1 && amt != null)
              Text(context.tr('your_share', {'a': Money.format(amt / _splitN), 'n': _splitN}),
                  style: context.tt.labelMedium?.copyWith(color: color)),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), children: [
            if (_type == TxnType.transfer) ...[
              _accountRow(context, m, context.t('from'), _account, (v) => setState(() => _account = v)),
              const SizedBox(height: 8),
              _accountRow(context, m, context.t('to'), _toAccount, (v) => setState(() => _toAccount = v)),
            ] else
              _categoryGrid(context, m),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                if (_type != TxnType.transfer)
                  _MetaButton(
                    icon: Icons.account_balance_wallet_outlined,
                    label: accountName(context, m.accountById(_account)),
                    onTap: () => _pickAccount(context, m),
                  ),
                _MetaButton(
                  icon: Icons.event_rounded,
                  label: context.dayLabel(_date, short: true),
                  onTap: () => _pickDate(context),
                ),
                if (_type == TxnType.expense && (_isNew || widget.txn?.split != null))
                  _MetaButton(
                    icon: Icons.call_split_rounded,
                    label: _splitN > 1 ? context.tr('split_n', {'n': _splitN}) : context.t('split'),
                    active: _splitN > 1,
                    onTap: _isNew ? () => _pickSplit(context) : null,
                  ),
                if (_type != TxnType.transfer)
                  _MetaButton(
                    icon: Icons.receipt_long_outlined,
                    label: _photos.isEmpty ? context.t('receipt') : '${context.t('receipt')} · ${_photos.length}',
                    active: _photos.isNotEmpty,
                    onTap: () => _pickReceipt(context),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              focusNode: _noteFocus,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: context.t(_type == TxnType.income ? 'note_hint_income' : 'note_hint_expense'),
                prefixIcon: const Icon(Icons.edit_note_rounded),
                isDense: true,
              ),
              onSubmitted: (_) => _noteFocus.unfocus(),
            ),
          ]),
        ),
        if (!keyboardOpen) _keypad(context, color),
      ]),
    );
  }

  Widget _categoryGrid(BuildContext context, MoneyStore m) {
    final cats = m.categoriesOf(_kind);
    final tk = context.tokens;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 520 ? 6 : 4;
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final cat in cats)
          SizedBox(
            width: w,
            child: _CatTile(
              emoji: cat.emoji,
              label: categoryName(context, cat),
              color: categoryColor(cat),
              selected: cat.id == _category,
              onTap: () => setState(() {
                _category = cat.id;
                _catTouched = true;
              }),
            ),
          ),
        SizedBox(
          width: w,
          child: _CatTile(
            emoji: '＋',
            label: context.t('add'),
            color: tk.textMuted,
            selected: false,
            onTap: () async {
              final id = await editCategory(context, kind: _kind);
              if (id != null && mounted) {
                setState(() {
                  _category = id;
                  _catTouched = true;
                });
              }
            },
          ),
        ),
      ]);
    });
  }

  Widget _accountRow(BuildContext context, MoneyStore m, String label, String value, ValueChanged<String> onPick) {
    return Row(children: [
      SizedBox(width: 48, child: Text(label, style: context.tt.labelLarge)),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final a in m.activeAccounts)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Text(a.emoji),
                  label: Text(accountName(context, a)),
                  selected: a.id == value,
                  onSelected: (_) => onPick(a.id),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }

  Widget _keypad(BuildContext context, Color color) {
    final tk = context.tokens;
    const rows = [
      ['7', '8', '9', '÷'],
      ['4', '5', '6', '×'],
      ['1', '2', '3', '−'],
      ['.', '0', '⌫', '+'],
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(color: tk.subtle, border: Border(top: BorderSide(color: tk.border))),
      child: Column(children: [
        for (final r in rows)
          Row(children: [
            for (final k in r)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Material(
                    color: '+−×÷'.contains(k) ? tk.subtleStrong : tk.card,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _key(k),
                      onLongPress: k == '⌫' ? () => setState(() => _expr = '') : null,
                      child: SizedBox(
                        height: 50,
                        child: Center(
                          child: k == '⌫'
                              ? Icon(Icons.backspace_outlined, size: 22, color: context.cs.onSurface)
                              : Text(k,
                                  style: context.tt.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: '+−×÷'.contains(k) ? context.cs.primary : null,
                                  )),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(context.t(_isNew ? 'save' : 'update')),
          ),
        ),
      ]),
    );
  }

  Future<void> _pickAccount(BuildContext context, MoneyStore m) async {
    final id = await showAppSheet<String>(context, builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(ctx.t('pay_from')),
            for (final a in m.activeAccounts)
              ListTile(
                leading: IconBadge(emoji: a.emoji, color: AppColors.swatch(a.color), size: 36),
                title: Text(accountName(ctx, a)),
                subtitle: Text(Money.format(m.accountBalance(a.id))),
                trailing: a.id == _account ? Icon(Icons.check_rounded, color: ctx.cs.primary) : null,
                onTap: () => Navigator.pop(ctx, a.id),
              ),
          ]),
        ),
      );
    });
    if (id != null && mounted) setState(() => _account = id);
  }

  Future<void> _pickDate(BuildContext context) async {
    final t0 = todayDate();
    final r = await showAppSheet<DateTime>(context, builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(ctx.t('date')),
            OptionTile(icon: Icons.today_rounded, title: ctx.t('today'), onTap: () => Navigator.pop(ctx, t0)),
            OptionTile(icon: Icons.history_rounded, title: ctx.t('yesterday'), onTap: () => Navigator.pop(ctx, addDays(t0, -1))),
            OptionTile(
                icon: Icons.history_toggle_off_rounded,
                title: ctx.fmtDate(addDays(t0, -2), 'EEEE, d MMM'),
                onTap: () => Navigator.pop(ctx, addDays(t0, -2))),
            OptionTile(
              icon: Icons.calendar_month_rounded,
              title: ctx.t('pick_from_calendar'),
              onTap: () async {
                final d = await showDatePicker(
                    context: ctx,
                    initialDate: _date,
                    // An older (imported) date must still be a valid initialDate.
                    firstDate: _date.year < 2000 ? DateTime(_date.year) : DateTime(2000),
                    lastDate: _date.year >= 2100 ? DateTime(_date.year + 1) : DateTime(2100));
                if (d != null && ctx.mounted) Navigator.pop(ctx, d);
              },
            ),
          ]),
        ),
      );
    });
    if (r != null && mounted) setState(() => _date = r);
  }

  Future<void> _pickSplit(BuildContext context) async {
    var n = _splitN < 2 ? 2 : _splitN;
    final ctrls = List.generate(20, (i) => TextEditingController(text: i < _splitNames.length ? _splitNames[i] : ''));
    final ok = await showAppSheet<bool>(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        final amt = _amount ?? 0;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(ctx.t('split_bill'), style: ctx.tt.titleLarge),
              const SizedBox(height: 4),
              Text(ctx.t('split_hint'), style: ctx.tt.bodySmall),
              const SizedBox(height: 14),
              Row(children: [
                Text(ctx.t('people_incl_you'), style: ctx.tt.bodyLarge),
                const Spacer(),
                IconButton.filledTonal(
                    onPressed: n <= 2 ? null : () => set(() => n--), icon: const Icon(Icons.remove_rounded)),
                SizedBox(width: 40, child: Text('$n', textAlign: TextAlign.center, style: ctx.tt.titleLarge)),
                IconButton.filledTonal(
                    onPressed: n >= 20 ? null : () => set(() => n++), icon: const Icon(Icons.add_rounded)),
              ]),
              const SizedBox(height: 6),
              Text(ctx.tr('each_pays', {'a': Money.format(amt / n)}),
                  style: ctx.tt.titleMedium?.copyWith(color: ctx.cs.primary)),
              const SizedBox(height: 12),
              for (var i = 0; i < n - 1; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: ctrls[i],
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: '${ctx.t('friend')} ${i + 1}',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      isDense: true,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(children: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t('no_split'))),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.t('done'))),
              ]),
            ]),
          ),
        );
      });
    });
    if (ok == null || !mounted) return;
    setState(() {
      if (ok) {
        _splitN = n;
        _splitNames = [for (var i = 0; i < n - 1; i++) ctrls[i].text.trim()];
      } else {
        _splitN = 1;
        _splitNames = [];
      }
    });
  }

  Future<void> _pickReceipt(BuildContext context) async {
    await showAppSheet(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: AttachmentPicker(
              urls: _photos,
              folder: 'receipts',
              label: ctx.t('receipt_photos'),
              onChanged: (l) {
                set(() => _photos = l);
                setState(() {});
              },
            ),
          ),
        );
      });
    });
  }
}

class _CatTile extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _CatTile({required this.emoji, required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    return Material(
      color: selected ? tk.tint(color) : tk.subtle,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? color : Colors.transparent, width: 1.6),
          ),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.labelSmall?.copyWith(
                  letterSpacing: 0,
                  color: selected ? color : context.cs.onSurface,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                )),
          ]),
        ),
      ),
    );
  }
}

class _MetaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  const _MetaButton({required this.icon, required this.label, this.active = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final c = active ? context.cs.primary : context.cs.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? context.cs.primaryContainer : tk.subtle,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: active ? c : tk.textMuted),
              const SizedBox(width: 6),
              Text(label, style: context.tt.labelMedium?.copyWith(color: c)),
            ]),
          ),
        ),
      ),
    );
  }
}
