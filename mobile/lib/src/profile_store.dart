import 'dart:convert';

import 'package:flutter/services.dart';

import 'character_look.dart';

/// One registered planter. The address is editable because the ESP32 can be an
/// access point (192.168.4.1) or, later, a station on a shared LAN.
class DeviceProfile {
  const DeviceProfile({
    required this.id,
    required this.deviceName,
    required this.charName,
    required this.host,
    required this.port,
    required this.characterId,
  });

  final String id;
  final String deviceName;
  final String charName;
  final String host;
  final int port;
  final String characterId;

  CharacterLook get look => CharacterLook.byId(characterId);

  DeviceProfile copyWith({
    String? deviceName,
    String? charName,
    String? host,
    int? port,
    String? characterId,
  }) => DeviceProfile(
    id: id,
    deviceName: deviceName ?? this.deviceName,
    charName: charName ?? this.charName,
    host: host ?? this.host,
    port: port ?? this.port,
    characterId: characterId ?? this.characterId,
  );

  Map<String, Object> toMap() => {
    'id': id,
    'deviceName': deviceName,
    'charName': charName,
    'host': host,
    'port': port,
    'character': characterId,
  };

  static DeviceProfile? fromMap(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final deviceName = value['deviceName'];
    final charName = value['charName'];
    final host = value['host'];
    final port = value['port'];
    final character = value['character'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 64 ||
        deviceName is! String ||
        deviceName.trim().isEmpty ||
        deviceName.length > 60 ||
        charName is! String ||
        charName.trim().isEmpty ||
        charName.length > 30 ||
        host is! String ||
        host.isEmpty ||
        host.length > 120 ||
        port is! int ||
        port < 1 ||
        port > 65535) {
      return null;
    }
    return DeviceProfile(
      id: id,
      deviceName: deviceName.trim(),
      charName: charName.trim(),
      host: host.trim(),
      port: port,
      characterId: CharacterLook.byId(character is String ? character : null)
          .id,
    );
  }
}

class ProfileSettings {
  const ProfileSettings({required this.devices, required this.activeId});

  final List<DeviceProfile> devices;
  final String activeId;

  static const defaults = ProfileSettings(
    devices: [
      DeviceProfile(
        id: 'planter-1',
        deviceName: 'Kebun Moss',
        charName: 'Moss',
        host: '192.168.4.1',
        port: 3333,
        characterId: 'moss',
      ),
    ],
    activeId: 'planter-1',
  );

  DeviceProfile get active {
    for (final device in devices) {
      if (device.id == activeId) return device;
    }
    return devices.isEmpty ? defaults.devices.first : devices.first;
  }

  ProfileSettings copyWith({List<DeviceProfile>? devices, String? activeId}) {
    final nextDevices = devices ?? this.devices;
    final nextActive = activeId ?? this.activeId;
    return ProfileSettings(
      devices: List<DeviceProfile>.unmodifiable(nextDevices),
      activeId: nextDevices.any((device) => device.id == nextActive)
          ? nextActive
          : (nextDevices.isEmpty ? defaults.activeId : nextDevices.first.id),
    );
  }

  ProfileSettings upsert(DeviceProfile device) {
    final next = List<DeviceProfile>.of(devices);
    final index = next.indexWhere((entry) => entry.id == device.id);
    if (index < 0) {
      next.add(device);
    } else {
      next[index] = device;
    }
    return copyWith(devices: next);
  }

  ProfileSettings remove(String id) {
    final next = devices.where((device) => device.id != id).toList();
    return copyWith(
      devices: next,
      activeId: next.isEmpty ? defaults.activeId : activeId,
    );
  }

  Map<String, Object> toMap() => {
    'schema': 'tunas-profiles-v1',
    'active': activeId,
    'devices': devices.map((device) => device.toMap()).toList(),
  };

  String get encoded => jsonEncode(toMap());

  static ProfileSettings parse(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schema'] != 'tunas-profiles-v1') {
        return defaults;
      }
      final rawDevices = decoded['devices'];
      if (rawDevices is! List) return defaults;
      final devices = rawDevices
          .map(DeviceProfile.fromMap)
          .whereType<DeviceProfile>()
          .take(6)
          .toList();
      if (devices.isEmpty) return defaults;
      final active = decoded['active'];
      return ProfileSettings(
        devices: List<DeviceProfile>.unmodifiable(devices),
        activeId: devices.any((device) => device.id == active)
            ? active as String
            : devices.first.id,
      );
    } on FormatException {
      return defaults;
    }
  }
}

class ProfileStore {
  const ProfileStore();

  static const _channel = MethodChannel('moss/profile');

  Future<ProfileSettings> read() async {
    try {
      final raw = await _channel.invokeMethod<String>('read');
      return ProfileSettings.parse(raw);
    } on PlatformException {
      return ProfileSettings.defaults;
    } on MissingPluginException {
      return ProfileSettings.defaults;
    } on FormatException {
      return ProfileSettings.defaults;
    }
  }

  Future<bool> write(ProfileSettings settings) async {
    try {
      await _channel.invokeMethod<void>('write', {'json': settings.encoded});
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
