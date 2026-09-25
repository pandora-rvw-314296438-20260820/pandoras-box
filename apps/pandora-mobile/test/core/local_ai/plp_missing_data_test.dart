import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/local_ai/plp_chat_fallback.dart';

Map<String, Object?> snapshot(Map<String, Object?> today) => {
      'organization': {'propertySlug': 'plp-boracay'},
      'today': today,
    };

String reply(String message, Map<String, Object?> today) =>
    PlpChatFallback.deterministicReply(
      message: message,
      enterpriseContext: snapshot(today),
    )!;

void main() {
  test('polite delegated actions never fall through to a snapshot answer', () {
    for (final message in [
      'Could you please update sales today?',
      'Can you please refund the guest?',
      'Would you please cancel the booking?',
      'Will you please approve the invoice?',
    ]) {
      final actionLike = !PlpChatFallback.isReadOnlyTurn(message);
      expect(actionLike, isTrue, reason: message);
      final deterministic = PlpChatFallback.deterministicReply(
        message: message, enterpriseContext: snapshot({'sales_today_php': 0}));
      final text = deterministic ??
          PlpChatFallback.continuityNotice(actionLike: actionLike);
      expect(deterministic, isNull);
      expect(text, contains('without repeating the action or claiming completion'));
      expect(text, contains('Check Activity'));
      expect(text, isNot(contains('₱0')));
    }
  });

  test('missing sales is unavailable, never a measured zero', () {
    final text = reply('sales today', {});
    expect(text, contains('unavailable'));
    expect(text, isNot(contains('₱0')));
    expect(text, contains('did not refresh a provider'));
  });
  test('real zero sales is preserved', () {
    expect(reply('sales today', {'sales_today_php': 0}), contains('₱0'));
    expect(reply('sales today', {'sales_today_php': '0'}), contains('₱0'));
  });
  test('malformed and nonfinite sales never crash or become zero', () {
    for (final value in <Object?>[
      null, '', 'invalid', 'NaN', 'Infinity', double.nan,
      double.infinity, -double.infinity, true, <String, Object?>{}, 1e100,
    ]) {
      final text = reply('sales today', {'sales_today_php': value});
      expect(text, contains('unavailable'), reason: '$value');
      expect(text, isNot(contains('₱0')), reason: '$value');
    }
  });
  test('valid negative sales remains a signed amount', () {
    expect(reply('sales today', {'sales_today_php': -1234}), contains('-₱1,234'));
  });
  test('sparse summary distinguishes known values from absent fields', () {
    final text = reply('summary', {'arrivals_today': 2, 'sales_today_php': 0});
    expect(text, contains('arrivals: 2'));
    expect(text, contains('sales: ₱0'));
    expect(text, contains('occupancy: unavailable'));
    expect(text, contains('departures: unavailable'));
  });
  test('unknown counts never become zero', () {
    for (final message in ['arrivals', 'departures', 'OTA conflicts', 'tasks']) {
      expect(reply(message, {}), contains('unavailable'));
    }
  });
  test('negative or fractional room counts are unavailable', () {
    for (final value in [-1, 1.5, 'NaN']) {
      expect(reply('available rooms', {'rooms_available': value, 'rooms_total': 3}),
          contains('room availability: unavailable; total rooms: 3'));
    }
  });
  test('out of range occupancy is unavailable but zero is valid', () {
    for (final value in [-1, 101, double.infinity]) {
      expect(reply('occupancy', {'occupancy_percent': value}),
          contains('occupancy: unavailable'));
    }
    expect(reply('occupancy', {'occupancy_percent': 0}), contains('0%'));
  });
  test('snapshot availability does not claim live right-now data', () {
    final text = reply('available rooms', {'rooms_available': 1, 'rooms_total': 3});
    expect(text, contains('in the snapshot'));
    expect(text, isNot(contains('right now')));
  });
  test('deterministic read fallback cannot answer an action as completed', () {
    expect(PlpChatFallback.deterministicReply(
      message: 'Update sales today', enterpriseContext: snapshot({})), isNull);
  });
}
