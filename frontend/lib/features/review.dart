import 'package:flutter/material.dart';
import '../core/book.dart';
import '../core/models.dart';
import '../shared/widgets.dart';
import 'ledger.dart';

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key});
  @override
  Widget build(BuildContext c) {
    final book = BookScope.of(c);
    return PageBody(
      children: [
        const SectionTitle('回顾'),
        if (book.periods.isEmpty)
          const Blank('从第一份盘点开始', '每一期的金额和你留下的话，都会出现在这里。'),
        for (final s in book.periods.reversed)
          Panel(
            child: DataRowLink(
              s.label,
              money(s.net),
              subtitle: [
                if (book.previous(s) == null)
                  '我的积累起点'
                else
                  '较上期 ${signed(s.net - book.previous(s)!.net)} 元',
                if (book.note(s.id).isNotEmpty) book.note(s.id),
              ].join('\n'),
              onTap: () => openPage(c, Receipt(s)),
            ),
          ),
      ],
    );
  }
}

class Receipt extends StatefulWidget {
  final Snapshot snapshot;
  const Receipt(this.snapshot, {super.key});
  @override
  State<Receipt> createState() => _ReceiptState();
}

class _ReceiptState extends State<Receipt> {
  TextEditingController? memo;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    memo ??= TextEditingController(
      text: BookScope.of(context).note(widget.snapshot.id),
    );
  }

  @override
  void dispose() {
    memo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final book = BookScope.of(c), s = widget.snapshot, prev = book.previous(s);
    int delta(Entry e) =>
        e.contribution - (prev?.find(e.id)?.contribution ?? 0);
    final updates = s.entries.where((e) => !e.same(prev?.find(e.id))).toList()
      ..sort((a, b) => delta(b).abs().compareTo(delta(a).abs()));
    return Scaffold(
      appBar: AppBar(title: const Text('本期盘点回执')),
      body: PageBody(
        children: [
          Text(s.label),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prev == null ? '首次盘点 · 净资产起点' : '较 ${day(prev.time)} 的净资产变化',
                ),
                Text(
                  prev == null ? money(s.net) : '${signed(s.net - prev.net)} 元',
                  style: Theme.of(c).textTheme.headlineMedium,
                ),
                Text('本期净资产 ${money(s.net)}'),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => openPeriod(c, s),
            child: const Text('查本期全部明细'),
          ),
          SectionTitle(prev == null ? '本次记录' : '哪些条目变了'),
          for (final e in updates)
            DataRowLink(
              e.name,
              prev == null ? money(e.cents) : '${signed(delta(e))} 元',
              subtitle:
                  '${changeLabel(e, prev?.find(e.id))} · ${money(e.cents)}',
              onTap: () => openEntry(c, s, e),
            ),
          if (updates.length < s.entries.length)
            DataRowLink(
              '${s.entries.length - updates.length} 项沿用上期',
              '核对',
              onTap: () => openPeriod(c, s),
            ),
          TextField(
            controller: memo,
            maxLength: 240,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '这次有什么值得记住的？'),
          ),
          FilledButton(
            onPressed: () {
              try {
                book.saveNote(s.id, memo!.text);
                message(c, '已保存到回顾');
              } catch (_) {
                message(c, '备注保存失败，请重试');
              }
            },
            child: const Text('保存到回顾'),
          ),
        ],
      ),
    );
  }
}
