import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:primitive_accumulation/app/app.dart';
import 'package:primitive_accumulation/core/book.dart';
import 'package:primitive_accumulation/core/theme.dart';
import 'package:primitive_accumulation/core/updates.dart';

void main() {
  test(
    'checks stable releases using numeric versions and handles service responses',
    () async {
      final installed = Version.parse('0.9.0+2');
      Future<UpdateResult> check(int status, [String tag = '']) async {
        final client = MockClient((request) async {
          expect(request.url.host, 'api.github.com');
          expect(request.url.path, endsWith('/releases/latest'));
          return http.Response(jsonEncode({'tag_name': tag}), status);
        });
        try {
          return await checkForUpdate(client, installed);
        } finally {
          client.close();
        }
      }

      expect(
        (await check(200, 'v0.10.0')).releasePage!.path,
        endsWith('/tag/v0.10.0'),
      );
      expect((await check(200, 'v0.9.0+3')).releasePage, isNotNull);
      expect((await check(200, 'v0.9.0+2')).releasePage, isNull);
      expect((await check(200, 'v0.9.0')).releasePage, isNull);
      expect((await check(404)).message, contains('暂未找到'));
      expect((await check(429)).message, contains('限制'));
      expect((await check(500)).message, contains('不可用'));
      await expectLater(check(200, 'unversioned'), throwsFormatException);
    },
  );

  testWidgets('mobile settings links appearance, backup and manual updates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final book = Book.example();
    addTearDown(book.dispose);
    PackageInfo.setMockInitialValues(
      appName: '原始积累',
      packageName: 'test',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: wealthTheme(Skin.grove, Brightness.light),
        builder: (_, child) => BookScope(book: book, child: child!),
        home: HomeShell(
          lock: () {},
          sessionActive: () => true,
          afterLock: (_) {},
        ),
      ),
    );
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.text('导出备份'), findsOneWidget);
    expect(find.text('从文件恢复'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.textContaining('当前版本 0.1.0'), findsOneWidget);
    await tester.tap(find.text('外观偏好'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.tap(find.text('暮紫星光'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('暮紫星光 · 深色'), findsOneWidget);
    await tester.tap(find.text('导出备份'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('设置备份密码'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('从文件恢复'), findsOneWidget);
  });
}
