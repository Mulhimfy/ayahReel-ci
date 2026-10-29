/// The version this binary was shipped to the stores as.
///
/// DO NOT EDIT THIS BY HAND — `tool/sync-version.sh` (or its `.ps1`
/// twin) writes it from `version:` in pubspec.yaml, CI runs that before
/// every build and patch, and test/version_sync_test.dart fails the
/// build if the two ever disagree. Bump pubspec.yaml; this follows.
///
/// It is the only thing [UpdateService] compares against, so a stale
/// value here makes the app either nag users who are already current or
/// stay silent for users who are behind — which is why it is generated
/// rather than remembered.
///
/// Deliberately a plain constant rather than a read of the installed
/// package: `package_info_plus` carries native code, and anything
/// native puts this whole feature out of reach of a Shorebird patch.
/// Dart-only, it ships over the air to users already on this release.
///
/// The build number is not part of it. The stores show, and users
/// think in, the marketing version; a build number that jumps for a
/// re-upload would otherwise read as a new version to every phone.
const kAppVersion = '1.0.11';

/// Compares two dotted versions â€” `1.0.10` is above `1.0.9`, not below
/// it, which is what a string compare would say.
///
/// Returns <0 when [a] is older, 0 when they match, >0 when [a] is
/// newer. Missing parts count as zero, so `1.0` == `1.0.0`. Anything
/// after a `+` or `-` (build metadata, pre-release tags) is ignored,
/// and a part that is not a number counts as zero rather than throwing:
/// a malformed line on the server must never crash a launch.
int compareVersions(String a, String b) {
  final x = _parts(a);
  final y = _parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

List<int> _parts(String v) {
  final core = v.trim().split(RegExp(r'[+\-]')).first;
  return core.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
}
