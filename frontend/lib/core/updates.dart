import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

const _repository = 'MycroftCooper/PrimitiveAccumulation';

class UpdateResult {
  final String message;
  final Uri? releasePage;
  const UpdateResult(this.message, [this.releasePage]);
}

Future<UpdateResult> checkForUpdate(
  http.Client client,
  Version installed,
) async {
  final response = await client
      .get(
        Uri.https('api.github.com', '/repos/$_repository/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      )
      .timeout(const Duration(seconds: 12));
  switch (response.statusCode) {
    case 404:
      return const UpdateResult('暂未找到已发布的正式版本。');
    case 403:
    case 429:
      return const UpdateResult('GitHub 暂时限制了访问，请稍后再试。');
    case 200:
      break;
    default:
      return const UpdateResult('更新服务暂时不可用，请稍后再试。');
  }
  final data = jsonDecode(utf8.decode(response.bodyBytes));
  if (data is! Map || data['tag_name'] is! String) {
    throw const FormatException();
  }
  final tag = data['tag_name'] as String;
  final latest = Version.parse(tag.replaceFirst(RegExp('^[vV]'), ''));
  if (latest <= installed) return const UpdateResult('当前已是最新版本。');
  final page = Uri(
    scheme: 'https',
    host: 'github.com',
    pathSegments: [..._repository.split('/'), 'releases', 'tag', tag],
  );
  return UpdateResult('发现新版本 $tag', page);
}
