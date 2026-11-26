import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primitive_accumulation/app/app.dart';
import 'package:primitive_accumulation/core/book.dart';
import 'package:primitive_accumulation/core/theme.dart';
import 'package:primitive_accumulation/features/settings.dart';

void main() {
  const biometrics = MethodChannel('primitive_accumulation/biometric');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const password = 'test-ledger-password';
  late Directory dir;
  late String path;
  String? saved;
  bool cancel = false;
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('biometric-ledger-');
    path = '${dir.path}/wealth.sqlite3';
    saved = null;
    cancel = false;
    messenger.setMockMethodCallHandler(paths, (_) async => dir.path);
    messenger.setMockMethodCallHandler(biometrics, (call) async {
      switch (call.method) {
        case 'available':
          return true;
        case 'enabled':
          return saved != null;
        case 'enable':
          saved = call.arguments as String;
          return null;
        case 'unlock':
          if (cancel) throw PlatformException(code: 'cancelled');
          return saved;
        case 'disable':
          saved = null;
          return null;
        default:
          throw MissingPluginException();
      }
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(biometrics, null);
    dir.deleteSync(recursive: true);
  });

  testWidgets('only a verified ledger password can enable biometric unlock', (
    t,
  ) async {
    final book = Book.open(path, password);
    addTearDown(book.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: wealthTheme(Skin.grove, Brightness.light),
        builder: (_, child) => BookScope(book: book, child: child!),
        home: SettingsPage(afterLock: (_) {}, sessionActive: () => true),
      ),
    );
    await t.pumpAndSettle();
    Future<void> enableWith(String value) async {
      await t.tap(find.text('生物识别解锁'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.byType(TextField), value);
      await t.tap(find.text('开启生物识别'));
      await t.pumpAndSettle();
    }

    await enableWith('incorrect');
    expect(saved, isNull);
    await enableWith(password);
    expect(saved, password);
    await t.tap(find.text('生物识别解锁'));
    await t.pumpAndSettle();
    expect(saved, isNull);
  });

  testWidgets(
    'a cancelled or stale credential leaves the encrypted ledger locked',
    (t) async {
      Book.open(path, password).dispose();
      saved = password;
      cancel = true;
      Book? opened;
      await t.runAsync(() async {
        await t.pumpWidget(
          MaterialApp(home: VaultGate(onOpen: (b) => opened = b)),
        );
        for (
          var i = 0;
          i < 100 && find.text('生物识别解锁').evaluate().isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await t.pump();
        }
      });
      Future<void> unlock() async {
        await t.tap(find.text('生物识别解锁'));
        await t.pumpAndSettle();
      }

      await unlock();
      expect(opened, isNull);
      expect(find.widgetWithText(TextField, '账本密码'), findsOneWidget);
      cancel = false;
      saved = 'obsolete';
      await unlock();
      expect(opened, isNull);
      saved = password;
      await unlock();
      expect(opened, isNotNull);
      opened?.dispose();
    },
  );
}
