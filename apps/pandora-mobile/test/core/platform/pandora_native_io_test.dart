import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/platform/pandora_native_io.dart';

void main() {
  test('selected contact requires a usable phone number', () {
    expect(
      () => PandoraPhoneContactSelection.fromMap(<Object?, Object?>{
        'displayName': 'Maria',
        'phoneNumber': '',
      }),
      throwsFormatException,
    );
  });

  test('selected contact normalizes returned system values', () {
    final selection = PandoraPhoneContactSelection.fromMap(<Object?, Object?>{
      'displayName': ' Maria ',
      'phoneNumber': ' 0917 555 0123 ',
    });
    expect(selection.displayName, 'Maria');
    expect(selection.phoneNumber, '0917 555 0123');
  });
}
