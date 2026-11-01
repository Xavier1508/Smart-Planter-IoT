import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/character_look.dart';
import 'package:smart_planter/src/profile_store.dart';

void main() {
  test('the three character looks are stable and distinct', () {
    expect(CharacterLook.all.map((look) => look.id), [
      'moss',
      'bara',
      'rintik',
    ]);
    expect(CharacterLook.all.map((look) => look.accessory).toSet().length, 3);
    expect(CharacterLook.byId('missing').id, 'moss');
    expect(CharacterLook.indexOf('rintik'), 2);
    expect(CharacterLook.indexOf('missing'), 0);
  });

  test('default profile stays usable without stored settings', () {
    final settings = ProfileSettings.parse(null);
    expect(settings.devices, hasLength(1));
    expect(settings.active.charName, 'Moss');
    expect(settings.active.host, '192.168.4.1');
    expect(settings.active.port, 3333);
  });

  test('profile JSON round-trips and keeps the active device', () {
    const device = DeviceProfile(
      id: 'planter-2',
      deviceName: 'Kebun Bara',
      charName: 'Bara',
      host: '192.168.4.2',
      port: 3333,
      characterId: 'bara',
    );
    final settings = ProfileSettings.defaults
        .upsert(device)
        .copyWith(activeId: 'planter-2');
    final restored = ProfileSettings.parse(settings.encoded);
    expect(restored.devices, hasLength(2));
    expect(restored.active.id, 'planter-2');
    expect(restored.active.look.id, 'bara');
  });

  test('invalid host, port and empty names are rejected', () {
    expect(
      DeviceProfile.fromMap({
        'id': 'x',
        'deviceName': '',
        'charName': 'Moss',
        'host': '192.168.4.1',
        'port': 3333,
        'character': 'moss',
      }),
      isNull,
    );
    expect(
      DeviceProfile.fromMap({
        'id': 'x',
        'deviceName': 'Kebun',
        'charName': 'Moss',
        'host': '',
        'port': 3333,
        'character': 'moss',
      }),
      isNull,
    );
    expect(
      DeviceProfile.fromMap({
        'id': 'x',
        'deviceName': 'Kebun',
        'charName': 'Moss',
        'host': '192.168.4.1',
        'port': 70000,
        'character': 'moss',
      }),
      isNull,
    );
  });

  test('removing the active device falls back to a valid profile', () {
    const second = DeviceProfile(
      id: 'planter-2',
      deviceName: 'Kebun Bara',
      charName: 'Bara',
      host: '192.168.4.2',
      port: 3333,
      characterId: 'bara',
    );
    final settings = ProfileSettings.defaults
        .upsert(second)
        .copyWith(activeId: 'planter-2');
    final next = settings.remove('planter-2');
    expect(next.devices, hasLength(1));
    expect(next.active.id, 'planter-1');
  });

  test('corrupt stored JSON never disables the default planter', () {
    expect(ProfileSettings.parse('{not json').devices, hasLength(1));
    expect(
      ProfileSettings.parse('{"schema":"wrong","devices":[]}').active.id,
      'planter-1',
    );
  });
}
