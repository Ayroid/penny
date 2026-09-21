/// Updates: the newest GitHub release, whether it is newer than this build,
/// and its APK for this phone.
///
/// Sideloaded, so there is no store to do this. The phone's own installer
/// still asks before anything is replaced — this only fetches the file.
library;

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Where `tool/release.sh --publish` puts releases. The GitHub API answers
/// without a token only for a public repo.
const _repo = 'Ayroid/penny';

typedef Release = ({String version, String apkUrl});

/// Whether [latest] is a higher `major.minor.patch` than [current]. A leading
/// `v` and anything after `+` or `-` are ignored.
bool isNewer(String latest, String current) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp('^v'), '')
      .split(RegExp('[+-]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final a = parts(latest), b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// The asset built for [abi] — release.sh makes one APK per ABI, and one for
/// the wrong processor will not install.
String? pickApk(List<dynamic> assets, String abi) {
  for (final a in assets) {
    final name = a['name'] as String;
    if (name.endsWith('.apk') && name.contains(abi)) {
      return a['browser_download_url'] as String;
    }
  }
  return null;
}

/// This phone's ABI, as release.sh spells it in the file name.
String get _abi => switch (Abi.current()) {
  Abi.androidArm => 'armeabi-v7a',
  Abi.androidX64 => 'x86_64',
  _ => 'arm64-v8a',
};

/// The newest published release, or null when there is none with an APK for
/// this phone. Throws on no network or a repo the API cannot see.
Future<Release?> latestRelease() async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(
      Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
    );
    req.headers.set('Accept', 'application/vnd.github+json');
    final res = await req.close();
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw HttpException('GitHub said ${res.statusCode}');
    }
    final json = jsonDecode(await res.transform(utf8.decoder).join());
    final url = pickApk(json['assets'] as List, _abi);
    if (url == null) return null;
    return (version: json['tag_name'] as String, apkUrl: url);
  } finally {
    client.close();
  }
}

/// Downloads the APK into the cache and returns its path. [onProgress] gets
/// 0 to 1 as it arrives, or null throughout if the size is not known.
Future<String> downloadApk(
  Release release, {
  void Function(double? fraction)? onProgress,
}) async {
  final client = HttpClient();
  try {
    // GitHub answers with a redirect to its file host; HttpClient follows it.
    final res = await (await client.getUrl(Uri.parse(release.apkUrl))).close();
    if (res.statusCode != 200) {
      throw HttpException('Download failed: ${res.statusCode}');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/penny-${release.version}.apk');
    final sink = file.openWrite();
    final total = res.contentLength; // -1 when the server does not say
    var got = 0;
    try {
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        onProgress?.call(total > 0 ? got / total : null);
      }
    } finally {
      await sink.close();
    }
    return file.path;
  } finally {
    client.close();
  }
}

/// The newer version waiting on GitHub, once a check has found one: what puts
/// the red dot on Settings and on its "Check for updates" row.
final updateWaiting = ValueNotifier<String?>(null);

/// Once per launch, from `main`, and silently: no network or no GitHub just
/// means no dot. Checking again is what the Settings row is for.
Future<void> checkOnLaunch() async {
  try {
    final latest = await latestRelease();
    final current = (await PackageInfo.fromPlatform()).version;
    if (latest != null && isNewer(latest.version, current)) {
      updateWaiting.value = latest.version;
    }
  } catch (_) {}
}
