import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/simple/project_intent_presentation.dart';

void main() {
  test('derives a clean project name and objective from supplied HTML', () {
    const html =
        '<!DOCTYPE html><html><head><title>EURO-FISH Trading Portal</title></head><body>hello</body></html>';
    expect(deriveProjectDisplayName(html), 'EURO-FISH Trading Portal');
    expect(
      deriveProjectStoredObjective(html),
      'Build and refine EURO-FISH Trading Portal.',
    );
    expect(
      projectPurposeForDisplay(html),
      'Build and refine EURO-FISH Trading Portal.',
    );
  });

  test('preserves ordinary owner intent', () {
    const intent =
        'Build a booking website for Porknyeta with delivery ordering';
    expect(deriveProjectDisplayName(intent), 'Porknyeta');
    expect(deriveProjectStoredObjective(intent), intent);
  });
}
