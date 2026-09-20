import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/local_ai/plp_chat_fallback.dart';

void main() {
  const context = <String, Object?>{
    'organization': <String, Object?>{
      'propertySlug': 'plp-boracay',
      'propertyName': 'PLP Boracay',
    },
    'today': <String, Object?>{
      'occupancy_percent': 66.67,
      'occupied_rooms': 2,
      'rooms_total': 3,
      'rooms_available': 1,
      'arrivals_today': 1,
      'departures_today': 1,
      'sales_today_php': 300000,
      'open_staff_tasks': 2,
      'open_ota_conflicts': 1,
    },
    'source': <String, Object?>{
      'state': 'healthy',
      'message': 'Reservations and payments are available.',
    },
  };

  test('answers occupancy from synchronized PLP context', () {
    final reply = PlpChatFallback.deterministicReply(
      message: "What's today's occupancy?",
      enterpriseContext: context,
    );
    expect(reply, contains('66.67%'));
    expect(reply, contains('2 of 3 rooms occupied'));
    expect(reply, contains('did not refresh a provider'));
  });

  test('summarizes PLP attention state without a model', () {
    final reply = PlpChatFallback.deterministicReply(
      message: 'What needs my attention?',
      enterpriseContext: context,
    );
    expect(reply, contains('2 open staff tasks'));
    expect(reply, contains('1 open OTA conflict'));
  });

  test('formats synchronized PLP sales', () {
    final reply = PlpChatFallback.deterministicReply(
      message: 'What are sales today?',
      enterpriseContext: context,
    );
    expect(reply, contains('₱300,000'));
  });

  test('refuses deterministic fallback for another workspace', () {
    final reply = PlpChatFallback.deterministicReply(
      message: 'What is occupancy?',
      enterpriseContext: const <String, Object?>{
        'organization': <String, Object?>{'propertySlug': 'other-workspace'},
      },
    );
    expect(reply, isNull);
  });

  test('classifies mutations conservatively', () {
    expect(PlpChatFallback.isReadOnlyTurn('What is occupancy?'), isTrue);
    expect(
      PlpChatFallback.isReadOnlyTurn('Create a housekeeping task for room 3'),
      isFalse,
    );
    expect(
      PlpChatFallback.isReadOnlyTurn('Can you cancel booking 103?'),
      isFalse,
    );
  });
}
