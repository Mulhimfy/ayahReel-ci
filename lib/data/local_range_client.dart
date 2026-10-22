import 'dart:io';

import 'package:http/http.dart' as http;

/// Answers requests for one URL from a copy of it on the phone, when the
/// copy is there, and sends everything else on to [inner].
///
/// A surah-file voice is read in byte ranges — its frame layout, then
/// the slice a reel or a listen needs (see `SurahSlice`). With the whole
/// surah kept for offline use, the same reads come from the disk: the
/// code that cuts the slice cannot tell the difference, and needs no
/// second way of doing it. `Range: bytes=a-b` and `bytes=a-` are
/// answered 206 with a `Content-Range`, a range past the end 416, and a
/// request without one 200 with the whole file.
class LocalRangeClient extends http.BaseClient {
  final http.Client inner;
  final Uri url;
  final File file;

  LocalRangeClient(this.inner, {required this.url, required this.file});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url != url || !file.existsSync()) return inner.send(request);
    final total = file.lengthSync();
    if (total == 0) return inner.send(request);
    final range = request.headers['Range'] ?? request.headers['range'];
    var from = 0;
    var to = total - 1;
    if (range != null) {
      final m = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range.trim());
      if (m == null) {
        return http.StreamedResponse(const Stream.empty(), 416,
            request: request, headers: {'content-range': 'bytes */$total'});
      }
      from = int.parse(m.group(1)!);
      if (m.group(2)!.isNotEmpty) to = int.parse(m.group(2)!);
      if (to >= total) to = total - 1;
      if (from >= total || from > to) {
        return http.StreamedResponse(const Stream.empty(), 416,
            request: request, headers: {'content-range': 'bytes */$total'});
      }
    }
    final length = to - from + 1;
    return http.StreamedResponse(
      file.openRead(from, to + 1),
      range == null ? 200 : 206,
      contentLength: length,
      request: request,
      headers: {
        'content-length': '$length',
        'accept-ranges': 'bytes',
        if (range != null) 'content-range': 'bytes $from-$to/$total',
      },
    );
  }

  @override
  void close() => inner.close();
}
