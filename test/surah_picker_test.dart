import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/widgets/surah_picker_sheet.dart';

/// The search box takes a surah, and an ayah after it in any of the
/// ways people write one.
void main() {
  test('a name or a number alone is a surah', () {
    expect(SurahPickerSheet.parse('baqarah'), const SurahQuery('baqarah'));
    expect(SurahPickerSheet.parse('36'), const SurahQuery('36'));
    expect(SurahPickerSheet.parse('  Ya Sin '), const SurahQuery('Ya Sin'));
    expect(SurahPickerSheet.parse(''), const SurahQuery(''));
  });

  test('a number after the surah is an ayah', () {
    expect(SurahPickerSheet.parse('2:255'), const SurahQuery('2', ayah: 255));
    expect(SurahPickerSheet.parse('2 255'), const SurahQuery('2', ayah: 255));
    expect(SurahPickerSheet.parse('baqarah 255'),
        const SurahQuery('baqarah', ayah: 255));
    expect(SurahPickerSheet.parse('Baqarah: 255'),
        const SurahQuery('Baqarah', ayah: 255));
    expect(SurahPickerSheet.parse('البقرة ٢٥٥'),
        const SurahQuery('البقرة', ayah: 255));
  });

  test('two numbers are a run', () {
    expect(SurahPickerSheet.parse('2:255-257'),
        const SurahQuery('2', ayah: 255, endAyah: 257));
    expect(SurahPickerSheet.parse('kahf 10 – 12'),
        const SurahQuery('kahf', ayah: 10, endAyah: 12));
    // Backwards is not a run; the first number stands.
    expect(SurahPickerSheet.parse('2:10-5'), const SurahQuery('2', ayah: 10));
  });

  test('a name with a number in it is still a name', () {
    expect(
        SurahPickerSheet.parse('al 1 :3'), const SurahQuery('al 1', ayah: 3));
  });
}
