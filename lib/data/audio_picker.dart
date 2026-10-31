import 'package:flutter/services.dart';

/// A recording picked off the phone: a copy the app can read, and the
/// name the user knows the file by.
typedef PickedAudio = ({String path, String name});

/// The "audio file" door on Android: the system document picker, with
/// the picked file streamed into the cache by MainActivity.
///
/// Not file_selector, which reads the whole file into memory on its way
/// across the channel — see `pickAudio` in MainActivity for what that
/// did to a full-surah recording.
abstract final class AudioPicker {
  static const _channel = MethodChannel('ayahreel/picker');

  /// Null when the user backs out. Throws a [PlatformException] when the
  /// picked file cannot be read or nothing on the phone opens documents.
  static Future<PickedAudio?> pick() async {
    final m = await _channel.invokeMapMethod<String, String>('pickAudio');
    final path = m?['path'];
    if (path == null || path.isEmpty) return null;
    return (path: path, name: m?['name'] ?? 'audio');
  }
}
