import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/notification_service.dart';

void main() {
  test('notification payload keeps the route and analysis text', () {
    final payload = NotificationPayload.fromMap({
      'route': 'home',
      'title': 'Tunas · Perlu perhatian',
      'body': 'Tanah kering; pompa terkunci.',
    });
    expect(payload, isNotNull);
    expect(payload!.route, 'home');
    expect(payload.title, contains('Tunas'));
    expect(payload.body, contains('pompa'));
  });

  test('malformed notification payloads are rejected', () {
    expect(NotificationPayload.fromMap(null), isNull);
    expect(NotificationPayload.fromMap({'route': 'home'}), isNull);
    expect(
      NotificationPayload.fromMap({'route': 1, 'title': 'x', 'body': 'y'}),
      isNull,
    );
  });
}
