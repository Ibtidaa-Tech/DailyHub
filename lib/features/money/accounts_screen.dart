import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currencies.dart';
import '../../core/localization.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/money_store.dart';
import '../../ui/kit.dart';
import 'money_ui.dart';
import 'txn_editor.dart';

/// Cash, bank, UPI, cards and wallets with live balances.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  static const kinds = ['cash', 'bank', 'upi', 'card', 'wallet', 'other'];
  static const kindEmoji = {'cash': '💵', 'bank': '🏦', 'upi': '📱', 'card': '💳', 'wallet': '👛', 'other': '💼'};

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final tk = context.tokens;
    final accs = m.activeAccounts;
    final archived = m.accounts.where((a) => a.archived).toList();
    return AppPage(
      title: context.t('m_accounts'),
      fab: FloatingActionButton.extended(
        onPressed: () => editAccount(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.t('add_account')),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: DhCard(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('total_balance'), style: context.tt.bodyMedium?.copyWith(color: tk.textMuted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(Money.format(m.netWorth),
                    style: context.tt.displaySmall?.copyWith(color: m.netWorth < 0 ? tk.expense : null)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => openTxnEditor(context, type: TxnType.transfer),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: Text(context.t('transfer_money')),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(child: SectionTitle(context.t('your_accounts'))),
        SliverList.list(children: [
          for (final a in accs) _AccountRow(account: a),
          if (accs.isEmpty) EmptyView(icon: Icons.account_balance_rounded, title: context.t('no_accounts'), compact: true),
        ]),
        if (archived.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(context.t('archived'))),
          SliverList.list(children: [for (final a in archived) _AccountRow(account: a)]),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(context.t('accounts_hint'), style: context.tt.bodySmall),
          ),
        ),
      ],
    );
  }

  static Future<void> editAccount(BuildContext context, {Account? account}) async {
    final m = context.read<MoneyStore>();
    final name = TextEditingController(text: account?.name ?? '');
    final opening = TextEditingController(
        text: account == null || account.opening == 0 ? '' : account.opening.toStringAsFixed(account.opening == account.opening.roundToDouble() ? 0 : 2));
    var kind = account?.kind ?? 'bank';
    var emoji = account?.emoji ?? kindEmoji[kind]!;
    var color = account?.color ?? m.accounts.length;
    await showAppSheet(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(ctx.t(account == null ? 'add_account' : 'edit_account'), style: ctx.tt.titleLarge),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in kinds)
                  ChoiceChip(
                    avatar: Text(kindEmoji[k]!),
                    label: Text(ctx.t('acc_$k')),
                    selected: kind == k,
                    onSelected: (_) => set(() {
                      if (emoji == kindEmoji[kind]) emoji = kindEmoji[k]!;
                      kind = k;
                    }),
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: ctx.t('acc_$kind'),
                  labelText: ctx.t('account_name'),
                  prefixIcon: Padding(padding: const EdgeInsets.all(12), child: Text(emoji, style: const TextStyle(fontSize: 18))),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: opening,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: ctx.t('opening_balance'),
                  prefixText: '${Money.symbol} ',
                  helperText: ctx.t('opening_balance_hint'),
                ),
              ),
              const SizedBox(height: 12),
              ColorDots(value: color % AppColors.swatches.length, onChanged: (v) => set(() => color = v)),
              const SizedBox(height: 18),
              Row(children: [
                if (account != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
                    icon: Icon(account.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
                    label: Text(ctx.t(account.archived ? 'restore' : 'archive')),
                    onPressed: () {
                      if (account.archived) {
                        m.saveAccount(account..archived = false);
                      } else {
                        m.deleteAccount(account);
                      }
                      Navigator.pop(ctx);
                    },
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final o = double.tryParse(opening.text.replaceAll(',', '').trim()) ?? 0.0;
                    final a = Account(
                      id: account?.id ?? '',
                      name: name.text.trim(),
                      kind: kind,
                      emoji: emoji,
                      color: color,
                      opening: o.isFinite ? o : 0,
                      archived: account?.archived ?? false,
                      order: account?.order ?? m.accounts.length,
                    );
                    m.saveAccount(a);
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

class _AccountRow extends StatelessWidget {
  final Account account;
  const _AccountRow({required this.account});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final bal = m.accountBalance(account.id);
    final tk = context.tokens;
    return DhCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountTxnsScreen(account: account))),
      onLongPress: () => AccountsScreen.editAccount(context, account: account),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(children: [
        IconBadge(emoji: account.emoji, color: AppColors.swatch(account.color), size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(accountName(context, account), style: context.tt.titleMedium),
            Text(context.t('acc_${account.kind}'), style: context.tt.bodySmall),
          ]),
        ),
        Text(Money.format(bal), style: context.tt.titleMedium?.copyWith(color: bal < 0 ? tk.expense : null)),
        IconButton(
          icon: const Icon(Icons.more_horiz_rounded),
          onPressed: () => AccountsScreen.editAccount(context, account: account),
        ),
      ]),
    );
  }
}

class AccountTxnsScreen extends StatelessWidget {
  final Account account;
  const AccountTxnsScreen({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final list = m.txns.where((t) => t.account == account.id || t.toAccount == account.id).take(300).toList();
    return AppPage(
      title: accountName(context, account),
      subtitle: Money.format(m.accountBalance(account.id)),
      slivers: [
        if (list.isEmpty)
          SliverToBoxAdapter(child: EmptyView(icon: Icons.receipt_long_rounded, title: context.t('no_txns'), compact: true))
        else
          SliverList.list(children: txnDayGroups(context, list)),
      ],
    );
  }
}
