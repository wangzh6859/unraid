import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// 通过 GitHub Releases API 检查是否有新版本。
///
/// 因为每次 CI 构建都使用同一份签名证书 + 严格递增的 versionCode
/// （见 .github/workflows/build-apk.yml），所以即使不走应用商店，
/// 用户直接下载新 APK 点击安装也会走"升级"流程，不需要先卸载旧版。
///
/// 版本对比口径：versionName 固定为 `1.0.<Actions 运行号>`（tag 同名），
/// versionCode 是"天数偏移 + 运行号"（防止工作流文件被改名后运行号重置），
/// 所以这里对比 versionName 而不是 versionCode。
class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;

  UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
  });
}

class UpdateService {
  /// 修改为你自己的 "用户名/仓库名"
  static const String githubRepo = 'wangzh6859/unraid';

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final resp = await http
          .get(
            Uri.parse(
                'https://api.github.com/repos/$githubRepo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tagName = (json['tag_name'] ?? '').toString(); // 例如 v1.0.42
      final assets = (json['assets'] as List?) ?? [];
      final apkAsset = assets.firstWhere(
        (a) => (a['name'] as String? ?? '').endsWith('.apk'),
        orElse: () => null,
      );
      if (apkAsset == null) return null;

      final packageInfo = await PackageInfo.fromPlatform();

      // 本机版本号：取 versionName 的最后一段数字（如 "1.0.42" -> 42）
      final currentVersion = int.tryParse(
              packageInfo.version.split('.').last.trim()) ??
          0;
      // 远端版本号：取 tag 的最后一段数字（如 "v1.0.42" -> 42）
      final latestVersion = int.tryParse(tagName.split('.').last.trim()) ?? 0;

      if (latestVersion <= currentVersion) return null;

      return UpdateInfo(
        latestVersion: tagName,
        downloadUrl: apkAsset['browser_download_url'] ?? json['html_url'],
        releaseNotes: json['body'] ?? '',
      );
    } catch (_) {
      // 静默失败：检查更新不应该打断用户正常使用
      return null;
    }
  }
}
