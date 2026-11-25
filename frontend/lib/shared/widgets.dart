import 'package:flutter/material.dart';

Future<T?> openPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            for (final child in children)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
          ],
        ),
      ),
    ),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  const Panel({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? action;
  const SectionTitle(this.text, {super.key, this.action});
  @override
  Widget build(BuildContext c) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: Theme.of(
            c,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      ?action,
    ],
  );
}

class Choices<T extends Object> extends StatelessWidget {
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  const Choices({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext c) => SegmentedButton<T>(
    segments: [
      for (final e in options.entries)
        ButtonSegment(value: e.key, label: Text(e.value)),
    ],
    selected: {value},
    onSelectionChanged: (s) => onChanged(s.single),
    showSelectedIcon: false,
  );
}

class Picker<T extends Object> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  const Picker({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext c) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        isExpanded: true,
        value: value,
        items: [
          for (final e in options.entries)
            DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    ),
  );
}

class DataRowLink extends StatelessWidget {
  final String title, value;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? dot;
  const DataRowLink(
    this.title,
    this.value, {
    super.key,
    this.subtitle,
    this.onTap,
    this.dot,
  });
  @override
  Widget build(BuildContext c) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: dot == null ? null : CircleAvatar(radius: 5, backgroundColor: dot),
    minLeadingWidth: 8,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: Text(value, style: Theme.of(c).textTheme.titleSmall),
    onTap: onTap,
  );
}

void message(BuildContext c, String text) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

class Blank extends StatelessWidget {
  final String title, body;
  const Blank(this.title, this.body, {super.key});
  @override
  Widget build(BuildContext c) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(c).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(body),
      ],
    ),
  );
}
