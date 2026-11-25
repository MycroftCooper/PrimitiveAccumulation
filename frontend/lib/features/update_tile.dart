import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/updates.dart';
import '../shared/widgets.dart';

class UpdateTile extends StatefulWidget {
  const UpdateTile({super.key});
  @override
  State<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<UpdateTile> {
  final client = http.Client();
  late final Future<PackageInfo> installed = PackageInfo.fromPlatform();
  UpdateResult? result;
  bool checking = false;

  @override
  void dispose() {
    client.close();
    super.dispose();
  }

  Future<void> check() async {
    if (checking) return;
    setState(() {
      checking = true;
      result = null;
    });
    UpdateResult next;
    try {
      final info = await installed;
      final version =
          info.version.contains('+') || int.tryParse(info.buildNumber) == null
          ? info.version
          : '${info.version}+${info.buildNumber}';
      next = await checkForUpdate(client, Version.parse(version));
    } on FormatException {
      next = const UpdateResult('无法识别版本信息，请稍后再试。');
    } catch (_) {
      next = const UpdateResult('检查失败，请确认网络连接后重试。');
    }
    if (!mounted) return;
    setState(() {
      checking = false;
      result = next;
    });
  }

  Future<void> openRelease(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Provide the same feedback when the platform has no browser handler.
    }
    if (mounted) message(context, '无法打开浏览器。');
  }

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.system_update_outlined),
          title: const Text('检查更新'),
          subtitle: FutureBuilder<PackageInfo>(
            future: installed,
            builder: (_, snapshot) {
              final info = snapshot.data;
              if (info == null) {
                return Text(snapshot.hasError ? '无法读取本机版本' : '正在读取版本…');
              }
              return Text(
                '当前版本 ${info.version}${info.buildNumber.isEmpty ? "" : "（${info.buildNumber}）"}',
              );
            },
          ),
          trailing: checking
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          onTap: checking ? null : check,
        ),
        if (result != null)
          Semantics(liveRegion: true, child: Text(result!.message)),
        if (result?.releasePage case final uri?)
          TextButton.icon(
            onPressed: () => openRelease(uri),
            icon: const Icon(Icons.open_in_new),
            label: const Text('查看发布页'),
          ),
      ],
    ),
  );
}
