import 'package:flutter/material.dart';
import '../core/book.dart';
import '../core/biometric_vault.dart';
import '../shared/widgets.dart';

class ChangePasswordPage extends StatefulWidget {
  final bool Function() sessionActive;
  const ChangePasswordPage({super.key, required this.sessionActive});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<ChangePasswordPage> {
  final old = TextEditingController();
  final next = TextEditingController();
  final confirmation = TextEditingController();
  bool verified = false, busy = false;
  String? error;

  @override
  void dispose() {
    old.dispose();
    next.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (verified && next.text != confirmation.text) {
      setState(() => error = '两次输入的新密码不一致。');
      return;
    }
    final book = BookScope.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    await Future<void>.delayed(Duration.zero);
    if (!mounted || !widget.sessionActive()) return;
    try {
      if (!verified) {
        verified = book.verifyPassword(old.text);
        if (!verified) error = '旧密码不正确，请重新输入。';
      } else {
        book.changePassword(old.text, next.text);
        if (BiometricVault.mobile) {
          try {
            await BiometricVault.disable();
          } catch (_) {
            // The rekeyed database already rejects the obsolete credential.
          }
        }
        if (mounted && widget.sessionActive()) Navigator.pop(context, true);
      }
    } on FormatException catch (e) {
      error = e.message;
    } catch (_) {
      verified = false;
      old.clear();
      next.clear();
      confirmation.clear();
      error = '无法修改密码，请关闭其他正在使用此账本的窗口，再验证当前密码。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    String label,
    TextEditingController controller, {
    bool last = true,
  }) => TextField(
    key: ValueKey(label),
    controller: controller,
    enabled: !busy,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: TextInputType.visiblePassword,
    textInputAction: last ? TextInputAction.done : TextInputAction.next,
    decoration: InputDecoration(labelText: label),
    onSubmitted: last ? (_) => submit() : null,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('修改账本密码')),
    body: PageBody(
      children: [
        if (verified) ...[
          const Text('旧密码已验证。请设置至少 6 位的新密码。'),
          field('新密码', next, last: false),
          field('再次输入新密码', confirmation),
        ] else
          field('旧密码', old),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(verified ? '保存新密码' : '验证旧密码'),
        ),
      ],
    ),
  );
}
