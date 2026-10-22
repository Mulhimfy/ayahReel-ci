import 'package:audioplayers/audioplayers.dart';

/// How often a player is asked where it is.
///
/// audioplayers installs a [FramePositionUpdater] on every [AudioPlayer]
/// it creates, which asks the platform for the position once per rendered
/// frame. On Android that question is `MediaPlayer.getCurrentPosition` — a
/// synchronous binder call into mediaserver, made on the platform main
/// thread — so a 120 Hz phone makes 120 of them a second for as long as
/// anything is playing. Play caught the ANR that follows on 1.0.4+14:
/// "Input dispatching timed out", main thread parked in
/// `IPCThreadState::transact` under `BpMediaPlayer::getCurrentPosition`,
/// with the preview's scene decoders loading underneath it.
///
/// Nothing here needs the position at frame rate. The preview keeps a
/// stopwatch running between events and interpolates; the alignment
/// waveform draws a playhead for a human to look at; the reciter samples
/// never ask at all.
extension PositionPolling on AudioPlayer {
  /// Ask the platform for the position every [interval] instead of every
  /// frame.
  void pollPositionEvery(Duration interval) {
    positionUpdater = TimerPositionUpdater(
      getPosition: getCurrentPosition,
      interval: interval,
    );
  }

  /// Stop asking altogether. For a player whose position nothing reads:
  /// with no updater, [onPositionChanged] is simply an empty stream.
  void stopPollingPosition() {
    positionUpdater = null;
  }
}
