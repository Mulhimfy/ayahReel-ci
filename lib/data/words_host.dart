/// Where the app's own word timing is served (see `OwnWords`), and the
/// key it asks with.
///
/// The timing is not public. It took a forced aligner days of runs to
/// make, so it is served by a Worker that answers only a request
/// carrying the app's key, and everything else, a wrong key included,
/// with a bare 404 (the private Mulhimfy/ayahreel-words repository has
/// the server and how the timing is made and published).
///
/// The key is not in the source, which the public CI mirror carries: the
/// build passes it in, `--dart-define=WORDS_KEY=…` from the CI secret
/// `WORDS_KEY`, in every workflow that builds the app. A build without it
/// (tests, a local run) has no own timing at all, as if the index named
/// no voice; the voices quran-align and QUL time are untouched.
abstract final class WordsHost {
  static const base = 'https://ayahreel-words.mulhimfy.workers.dev/v1';

  static const _key = String.fromEnvironment('WORDS_KEY');

  /// Whether this build can read the timing at all.
  static bool get enabled => _key.isNotEmpty;

  /// What every request for it carries.
  static Map<String, String> get headers => const {'x-ayahreel-key': _key};
}
