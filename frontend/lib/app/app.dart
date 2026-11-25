import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import '../core/book.dart';
import '../core/theme.dart';
import '../features/growth.dart';
import '../features/ledger.dart';
import '../features/review.dart';
import '../features/settings.dart';
import '../features/stocktake.dart';
import '../shared/widgets.dart';

class WealthApp extends StatefulWidget {
  const WealthApp({super.key});
  @override
  State<WealthApp> createState() => _WealthAppState();
}

class _WealthAppState extends State<WealthApp> with WidgetsBindingObserver {
  Book? book;
  final homeKey = GlobalKey<_HomeShellState>();
  BackupPickerResult? pendingBackup;

  void receiveBackup(BackupPickerResult result) {
    if (!mounted) return;
    pendingBackup = result;
    deliverBackup();
  }

  void deliverBackup() {
    final home = homeKey.currentState, result = pendingBackup;
    if (home == null || result == null || book?.demo != false) return;
    pendingBackup = null;
    home.openSettings(result);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && book?.demo == false) lock();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void unlock(Book next) {
    next.addListener(changed);
    setState(() => book = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) deliverBackup();
    });
  }

  void lock() {
    final old = book;
    if (old == null) return;
    old.removeListener(changed);
    setState(() => book = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    book?.removeListener(changed);
    book?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final b = book, skin = Skin.find(b?.skin ?? 'grove');
    return MaterialApp(
      key: ObjectKey(b),
      debugShowCheckedModeBanner: false,
      title: '原始积累',
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: wealthTheme(skin, Brightness.light),
      darkTheme: wealthTheme(skin, Brightness.dark),
      themeMode: b?.mode ?? ThemeMode.system,
      builder: (_, child) =>
          b == null ? child! : BookScope(book: b, child: child!),
      home: b == null
          ? VaultGate(onOpen: unlock)
          : HomeShell(
              key: homeKey,
              lock: lock,
              afterLock: receiveBackup,
              sessionActive: () => identical(book, b),
            ),
    );
  }
}

class VaultGate extends StatefulWidget {
  final ValueChanged<Book> onOpen;
  const VaultGate({super.key, required this.onOpen});
  @override
  State<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<VaultGate> {
  final pass = TextEditingController(), confirm = TextEditingController();
  String? path, error;
  bool exists = false, busy = false;
  @override
  void initState() {
    super.initState();
    locate();
  }

  Future<void> locate() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final file = File('${dir.path}/wealth.sqlite3');
      final found = await file.exists() && await file.length() > 0;
      if (mounted) {
        setState(() {
          path = file.path;
          exists = found;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '无法访问本机存储，请重试。');
    }
  }

  @override
  void dispose() {
    pass.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> enter() async {
    if (busy || path == null) return;
    if (pass.text.isEmpty ||
        (!exists && (pass.text.length < 6 || pass.text != confirm.text))) {
      setState(() => error = exists ? '请输入解锁密码。' : '请设置至少 6 位密码，并确认两次输入一致。');
      return;
    }
    setState(() => busy = true);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    try {
      final b = Book.open(path!, pass.text);
      widget.onOpen(b);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = exists ? '解锁失败，请核对密码及账本文件。' : '未能创建加密账本，请检查本机存储。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('原始积累')),
    body: PageBody(
      children: [
        const Icon(Icons.savings_outlined, size: 64),
        SectionTitle(exists ? '打开我的账本' : '我的第一份财富手账'),
        Text(
          exists ? '输入本机账本密码，继续盘点。' : '账本保存在本机。卸载前请在「设置」导出备份。换机后可创建账本，再从备份恢复。',
        ),
        TextField(
          controller: pass,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(labelText: exists ? '账本密码' : '设置账本密码'),
          onSubmitted: exists ? (_) => enter() : null,
        ),
        if (!exists)
          TextField(
            controller: confirm,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '再次输入密码'),
            onSubmitted: (_) => enter(),
          ),
        if (error != null)
          Text(error!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
        FilledButton(
          onPressed: busy || path == null ? null : enter,
          child: Text(exists ? '解锁账本' : '创建本机账本'),
        ),
        if (path == null && error != null)
          TextButton(onPressed: locate, child: const Text('重试')),
        OutlinedButton(
          onPressed: busy
              ? null
              : () {
                  try {
                    widget.onOpen(Book.example());
                  } catch (_) {
                    setState(() => error = '体验账本打开失败。');
                  }
                },
          child: const Text('先体验示例账本'),
        ),
        const Text('体验账本使用示例数据，退出后清空。'),
      ],
    ),
  );
}

class HomeShell extends StatefulWidget {
  final VoidCallback lock;
  final ValueChanged<BackupPickerResult> afterLock;
  final bool Function() sessionActive;
  const HomeShell({
    super.key,
    required this.lock,
    required this.sessionActive,
    required this.afterLock,
  });
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  void openSettings([BackupPickerResult? pending]) {
    openPage(
      context,
      SettingsPage(
        afterLock: widget.afterLock,
        sessionActive: widget.sessionActive,
        pending: pending,
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final b = BookScope.of(c);
    return Scaffold(
      appBar: AppBar(
        title: Text(b.demo ? '原始积累 · 体验账本' : '原始积累'),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: b.demo ? '退出体验' : '锁定账本',
            onPressed: widget.lock,
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: IndexedStack(
        index: tab,
        children: const [GrowthPage(), LedgerPage(), ReviewPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) {
          if (i == 3) {
            startStocktake(c);
          } else {
            setState(() => tab = i);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            label: '成长',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: '账本',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: '回顾'),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            label: '盘点一次',
          ),
        ],
      ),
    );
  }
}
