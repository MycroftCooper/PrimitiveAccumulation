import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/backup.dart';
import '../core/book.dart';
import 'update_tile.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../shared/widgets.dart';

/// Only ciphertext or a status message can survive the automatic app lock.
class BackupPickerResult {
  final Uint8List? bytes;
  final String? message;
  const BackupPickerResult.file(Uint8List this.bytes) : message = null;
  const BackupPickerResult.status(String this.message) : bytes = null;
}

class SettingsPage extends StatefulWidget {
  final ValueChanged<BackupPickerResult> afterLock;
  final BackupPickerResult? pending;
  final bool Function() sessionActive;
  const SettingsPage({
    super.key,
    required this.afterLock,
    required this.sessionActive,
    this.pending,
  });

  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> {
  bool busy = false;
  String? status;

  @override
  void initState() {
    super.initState();
    final pending = widget.pending;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) run(() => handle(pending));
      });
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await operation();
    } on FormatException catch (e) {
      if (mounted) status = e.message;
    } on StateError catch (e) {
      if (mounted) status = e.message;
    } catch (_) {
      if (mounted) status = '操作失败，请检查文件位置、系统权限和可用空间后重试。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> password(bool create) => showDialog<String>(
    context: context,
    builder: (_) => _PasswordDialog(create: create),
  );

  Future<void> handle(BackupPickerResult result) async {
    if (result.bytes == null) {
      setState(() => status = result.message);
      return;
    }
    final book = BookScope.of(context);
    final key = await password(false);
    if (key == null || !mounted) return;
    final data = await BackupFile.decrypt(result.bytes!, key);
    if (!mounted) return;
    final preview = book.restorePreview;
    final last = data.snapshots.lastOrNull;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('恢复这份备份？'),
        scrollable: true,
        content: Text(
          [
            '备份中有 ${data.snapshots.length} 期盘点、${data.notes.values.where((v) => v.isNotEmpty).length} 条回顾备注。',
            if (last != null) '最近一期：${day(last.time)}，净资产 ${money(last.net)}。',
            if (data.preferences.containsKey('draft')) '包含一份未提交的草稿。',
            '确认后将替换当前账本的 ${preview.periodCount} 期记录、草稿、目标和偏好。本机解锁密码保持原样。',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认替换'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    book.restore(data, expectedRevision: preview.revision);
    setState(() => status = '已恢复 ${data.snapshots.length} 期盘点，可返回账本查看。');
  }

  Future<void> withPicker(Future<BackupPickerResult?> Function() choose) async {
    final afterLock = widget.afterLock, sessionActive = widget.sessionActive;
    final personal = !BookScope.of(context).demo;
    BackupPickerResult? result;
    try {
      result = await choose();
    } catch (_) {
      result = const BackupPickerResult.status('无法读写所选文件，请检查文件位置和权限后重试。');
    }
    if (result == null) return;
    if (mounted && sessionActive()) {
      await handle(result);
    } else if (personal) {
      afterLock(result);
    }
  }

  Future<void> exportFile() async {
    final book = BookScope.of(context);
    final key = await password(true);
    if (key == null || !mounted) return;
    final bytes = await BackupFile.encrypt(book.exportData(), key);
    if (!mounted) return;
    final now = DateTime.now();
    final name =
        '原始积累-${day(now)}-${now.hour.toString().padLeft(2, "0")}${now.minute.toString().padLeft(2, "0")}${now.second.toString().padLeft(2, "0")}.pabackup';
    await withPicker(() async {
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        dialogTitle: '保存账本备份',
      );
      return uri == null
          ? null
          : const BackupPickerResult.status('加密备份已保存到所选位置。');
    });
  }

  Future<void> importFile() => withPicker(() async {
    final file = await FilePicker.pickFile(dialogTitle: '选择账本备份');
    if (file == null) return null;
    final size = await file.length();
    if (size != null && size > BackupFile.maxBytes) {
      return const BackupPickerResult.status('文件超过 32 MiB，请选择有效的账本备份。');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (bytes.length + chunk.length > BackupFile.maxBytes) {
        return const BackupPickerResult.status('文件超过 32 MiB，请选择有效的账本备份。');
      }
      bytes.add(chunk);
    }
    return BackupPickerResult.file(bytes.takeBytes());
  });

  @override
  Widget build(BuildContext c) {
    final book = BookScope.of(c);
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: PageBody(
          children: [
            Panel(
              child: ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('外观偏好'),
                subtitle: Text(
                  '${Skin.find(book.skin).title} · ${_modeLabels[book.mode]}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : () => openPage(c, const AppearancePage()),
              ),
            ),
            const SectionTitle('账本备份'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.demo
                        ? '当前为体验账本，恢复的数据将在退出体验后清空。'
                        : '备份包含每期明细、回顾备注、盘点草稿、财富目标和外观设置。',
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.file_upload_outlined),
                    title: const Text('导出备份'),
                    subtitle: const Text('设置备份密码，选择保存位置'),
                    onTap: busy ? null : () => run(exportFile),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.file_download_outlined),
                    title: const Text('从文件恢复'),
                    subtitle: const Text('选择备份，预览后替换当前账本'),
                    onTap: busy ? null : () => run(importFile),
                  ),
                  if (busy)
                    const LinearProgressIndicator(semanticsLabel: '正在处理备份'),
                  if (status != null)
                    Semantics(liveRegion: true, child: Text(status!)),
                ],
              ),
            ),
            const UpdateTile(),
          ],
        ),
      ),
    );
  }
}

const _modeLabels = {
  ThemeMode.system: '跟随系统',
  ThemeMode.light: '浅色',
  ThemeMode.dark: '深色',
};

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});
  @override
  Widget build(BuildContext c) {
    final book = BookScope.of(c);
    void appearance(ThemeMode mode, String skin) {
      try {
        book.appearance(mode, skin);
      } catch (_) {
        message(c, '外观设置保存失败，请重新打开账本。');
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('外观偏好')),
      body: PageBody(
        children: [
          const SectionTitle('明暗模式'),
          Choices<ThemeMode>(
            options: _modeLabels,
            value: book.mode,
            onChanged: (v) => appearance(v, book.skin),
          ),
          const SectionTitle('主题配色'),
          for (final skin in Skin.values)
            Panel(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: skin.seed),
                title: Text(skin.title),
                trailing: book.skin == skin.id ? const Icon(Icons.check) : null,
                onTap: () => appearance(book.mode, skin.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  final bool create;
  const _PasswordDialog({required this.create});
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final first = TextEditingController(), second = TextEditingController();
  String? error;

  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }

  void submit() {
    if (first.text.isEmpty ||
        (widget.create &&
            (first.text.length < 8 || first.text != second.text))) {
      setState(
        () => error = widget.create ? '请填写至少 8 位密码，并确认两次一致。' : '请输入备份密码。',
      );
      return;
    }
    Navigator.pop(context, first.text);
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    scrollable: true,
    title: Text(widget.create ? '设置备份密码' : '打开加密备份'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.create) const Text('恢复文件时需要这个密码，请妥善保管。'),
        TextField(
          controller: first,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: '备份密码'),
          onSubmitted: widget.create ? null : (_) => submit(),
        ),
        if (widget.create)
          TextField(
            controller: second,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '再次输入备份密码'),
            onSubmitted: (_) => submit(),
          ),
        if (error != null)
          Text(error!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
      FilledButton(
        onPressed: submit,
        child: Text(widget.create ? '选择保存位置' : '预览备份'),
      ),
    ],
  );
}
