import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where the files a render is made from live: verse cards, flattened
/// backdrops, scrims, bundled sceneries copied out. (The encode's own
/// output stays in the cache folder, which is the one the share sheets'
/// file providers can hand to another app.)
///
/// Not Android's cache folder. Android empties an app's cache whenever
/// the phone runs short of room, without asking and while the app is
/// running — and on a phone that is nearly full, a save is what makes it
/// short. A Galaxy M13 lost its flattened backdrop that way between its
/// drawing and the encode on every save it tried (2026-10-04/05:
/// "ayah_bgflat_….png: No such file or directory"), and the bundled
/// scenery copied beside it went with it. So on Android the render
/// works in a folder of the app's own, which only the app empties
/// ([VideoRenderer.sweepCache], the storage sheet). iOS leaves its
/// temporary folder alone while the app runs, so there it stays.
Future<Directory> renderDir() async {
  if (!Platform.isAndroid) return getTemporaryDirectory();
  final d = Directory('${(await getApplicationSupportDirectory()).path}/render');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}
