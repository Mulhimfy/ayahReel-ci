import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/settings_service.dart';

/// The Home shelf opens on what was chosen last: the switch on its
/// heading between the reels and the quiz's rounds is kept with the
/// settings, so closing the app doesn't put it back on the reels.
void main() {
  test('the shelf choice is kept, and the reels are where it starts', () {
    expect(AppSettings.fromJson(const {}).homeRounds, isFalse);
    expect(AppSettings.defaults.homeRounds, isFalse);
    final rounds = AppSettings.defaults.copyWith(homeRounds: true);
    expect(AppSettings.fromJson(rounds.toJson()).homeRounds, isTrue);
    expect(
        AppSettings.fromJson(rounds.copyWith(homeRounds: false).toJson())
            .homeRounds,
        isFalse);
  });
}
