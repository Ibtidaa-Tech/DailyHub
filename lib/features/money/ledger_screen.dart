import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/currencies.dart';
import '../../core/format.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../ui/kit.dart';
import 'money_ui.dart';

/// Lend & borrow ("udhaar") — who owes whom, with repayments and reminders.
class LedgerScreen extends StatelessWidget {
  const LedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final tk = context.tokens;
    final people = m.people;
    final open = people.where((p) => p.net.abs() > 0.009).toList();
    final settled = people.where((p) => p.net.abs() <= 0.009).toList();
    return AppPage(
      title: context.t('m_ledger'),
      subtitle: context.t('ledger_sub'),
      fab: FloatingActionButton.extended(
        onPressed: () => editDebt(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('add_entry')),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Row(children: [
            Expanded(
              child: DhCard(
                color: tk.tint(tk.income),
                borderColor: Colors.transparent,
                child: StatBlock(label: context.t('you_will_get'), value: Money.format(m.toReceive), color: tk.income, icon: Icons.south_west_rounded),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DhCard(
                color: tk.tint(tk.expense),
                borderColor: Colors.transparent,
                child: StatBlock(label: context.t('you_owe'), value: Money.format(m.toPay), color: tk.expense, icon: Icons.north_east_rounded),
              ),
            ),
          ]),
        ),
        if (people.isEmpty)
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.handshake_rounded,
              color: AppColors.mJournal,
              title: context.t('no_debts'),
              message: context.t('no_debts_msg'),
              actionLabel: context.t('add_entry'),
              onAction: () => editDebt(context),
            ),
          ),
        if (open.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('open_balances'))),
          SliverList.list(children: [for (final p in open) _PersonRow(p: p)]),
        ],
        if (settled.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('settled'))),
          SliverList.list(children: [for (final p in settled) _PersonRow(p: p)]),
        ],
      ],
    );
  }

  static Future<void> editDebt(BuildContext context, {Debt? debt, String? person}) async {
    final m = context.read<MoneyStore>();
    final d = debt == null ? Debt(person: person ?? '') : Debt.fromMap({...debt.toMap(), 'id': debt.id});
    final name = TextEditingController(text: d.person);
    final phone = TextEditingController(text: d.phone);
    final amount = TextEditingController(text: d.amount == 0 ? '' : d.amount.toStringAsFixed(d.amount == d.amount.roundToDouble() ? 0 : 2));
    final note = TextEditingController(text: d.note);
    final known = m.people.map((p) => p.person).toList();
    await showAppSheet(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(ctx.t(debt == null ? 'add_entry' : 'edit_entry'), style: ctx.tt.titleLarge),
              const SizedBox(height: 12),
              PillTabs<String>(
                items: [('lent', ctx.t('i_lent')), ('borrowed', ctx.t('i_borrowed'))],
                value: d.kind,
                onChanged: (v) => set(() => d.kind = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: ctx.t('person'), prefixIcon: const Icon(Icons.person_outline_rounded)),
              ),
              if (known.isNotEmpty && debt == null) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final k in known.take(8))
                    ActionChip(label: Text(k), onPressed: () => set(() => name.text = k)),
                ]),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: ctx.t('amount'), prefixText: '${Money.symbol} '),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: ctx.t('note'), prefixIcon: const Icon(Icons.notes_rounded)),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: FormFieldButton(
                    icon: Icons.event_available_rounded,
                    label: ctx.t('due_date_optional'),
                    value: parseDay(d.due) == null ? ctx.t('none') : ctx.fmtDate(parseDay(d.due)!, 'd MMM yyyy'),
                    onTap: () async {
                      final init = parseDay(d.due) ?? addDays(todayDate(), 7);
                      final x = await showDatePicker(
                          context: ctx,
                          initialDate: init,
                          firstDate: init.year < 2020 ? DateTime(init.year) : DateTime(2020),
                          lastDate: DateTime(2100));
                      if (x != null) set(() => d.due = dayKey(x));
                    },
                  ),
                ),
                if (d.due.isNotEmpty)
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => set(() => d.due = '')),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: ctx.t('phone_optional'), prefixIcon: const Icon(Icons.phone_outlined)),
              ),
              const SizedBox(height: 18),
              Row(children: [
                if (debt != null)
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: ctx.tokens.danger),
                    onPressed: () {
                      final data = m.deleteDebt(debt);
                      Navigator.pop(ctx);
                      showUndo(context, context.t('entry_deleted'), () => m.restore('debts', debt.id, data));
                    },
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final a = double.tryParse(amount.text.replaceAll(',', '').trim()) ?? 0;
                    if (name.text.trim().isEmpty || a <= 0 || !a.isFinite) {
                      showToast(ctx, ctx.t('name_and_amount'));
                      return;
                    }
                    d
                      ..person = name.text.trim()
                      ..phone = phone.text.trim()
                      ..amount = a
                      ..note = note.text.trim();
                    m.saveDebt(d);
                    Navigator.pop(ctx);
                  },
                  child: Text(ctx.t('save')),
                ),
              ]),
            ]),
          ),
        );
      });
    });
  }
}

class _PersonRow extends StatelessWidget {
  final PersonBalance p;
  const _PersonRow({required this.p});

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final owesYou = p.net > 0;
    return DhCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PersonLedgerScreen(person: p.person))),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(children: [
        InitialsAvatar(p.person, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.person, style: context.tt.titleSmall),
            Text(
              p.net.abs() <= 0.009 ? context.t('all_settled') : context.t(owesYou ? 'owes_you' : 'you_owe_them'),
              style: context.tt.bodySmall,
            ),
          ]),
        ),
        if (p.net.abs() > 0.009)
          Text(Money.format(p.net.abs()), style: context.tt.titleSmall?.copyWith(color: owesYou ? tk.income : tk.expense)),
      ]),
    );
  }
}

/// All entries with one person, with repay / settle / remind.
class PersonLedgerScreen extends StatelessWidget {
  final String person;
  const PersonLedgerScreen({super.key, required this.person});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final tk = context.tokens;
    PersonBalance? pb;
    for (final x in m.people) {
      if (x.person.toLowerCase() == person.toLowerCase()) pb = x;
    }
    final items = pb?.items ?? const <Debt>[];
    final net = pb?.net ?? 0;
    final phone = items.map((d) => d.phone).firstWhere((p) => p.isNotEmpty, orElse: () => '');
    return AppPage(
      title: person,
      subtitle: net.abs() <= 0.009
          ? context.t('all_settled')
          : '${context.t(net > 0 ? 'owes_you' : 'you_owe_them')} ${Money.format(net.abs())}',
      fab: FloatingActionButton(
        onPressed: () => LedgerScreen.editDebt(context, person: person),
        child: const Icon(Icons.add_rounded),
      ),
      slivers: [
        if (net > 0.009)
          SliverToBoxAdapter(
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: Text(context.t('send_reminder')),
                  onPressed: () {
                    final msg = context.tr('reminder_msg', {'p': person, 'a': Money.format(net)});
                    Share.share(msg);
                  },
                ),
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: const Text('WhatsApp'),
                    onPressed: () {
                      final msg = context.tr('reminder_msg', {'p': person, 'a': Money.format(net)});
                      final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
                      launchUrl(Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(msg)}'),
                          mode: LaunchMode.externalApplication);
                    },
                  ),
                ),
              ],
            ]),
          ),
        SliverList.list(children: [
          for (final d in items)
            DhCard(
              onTap: () => LedgerScreen.editDebt(context, debt: d),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Pill(context.t(d.isLent ? 'i_lent' : 'i_borrowed'), color: d.isLent ? tk.income : tk.expense),
                  const SizedBox(width: 8),
                  Text(context.fmtDate(parseDay(d.date) ?? todayDate(), 'd MMM yyyy'), style: context.tt.bodySmall),
                  const Spacer(),
                  Text(Money.format(d.amount), style: context.tt.titleSmall),
                ]),
                if (d.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(d.note)),
                if (d.payments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ProgressBar(value: d.amount == 0 ? 0 : d.paid / d.amount, color: tk.success, height: 6),
                  const SizedBox(height: 4),
                  Text(context.tr('repaid_of', {'a': Money.format(d.paid), 'b': Money.format(d.amount)}), style: context.tt.bodySmall),
                ],
                if (parseDay(d.due) != null && !d.settled)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${context.t('due')}: ${context.dayLabel(parseDay(d.due)!)}',
                        style: context.tt.bodySmall?.copyWith(
                            color: parseDay(d.due)!.isBefore(todayDate()) ? tk.danger : null)),
                  ),
                const SizedBox(height: 6),
                Row(children: [
                  if (d.settled)
                    Pill(context.t('settled'), color: tk.success, icon: Icons.check_rounded)
                  else ...[
                    TextButton.icon(
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: Text(context.t('record_payment')),
                      onPressed: () async {
                        final v = await promptAmount(context, title: context.t('record_payment'), initial: d.remaining);
                        if (v != null && v > 0) m.addDebtPayment(d, v);
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: Text(context.t('settle')),
                      onPressed: () => m.settleDebt(d, true),
                    ),
                  ],
                ]),
              ]),
            ),
        ]),
      ],
    );
  }
}
