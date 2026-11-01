import 'package:flutter/material.dart';

/// A small, deliberately curated set of character looks. The 3D avatar is built
/// from primitives, so a look is a palette plus one recognizable accessory and
/// a movement temperament rather than a separate rigged model.
enum CharacterAccessory { leafCrown, sunHat, rainCloud }

class CharacterLook {
  const CharacterLook({
    required this.id,
    required this.name,
    required this.tagline,
    required this.skin,
    required this.hair,
    required this.clothes,
    required this.accent,
    required this.accessory,
    required this.motionSpeed,
  });

  final String id;
  final String name;
  final String tagline;
  final int skin;
  final int hair;
  final int clothes;
  final int accent;
  final CharacterAccessory accessory;

  /// Multiplier for idle sway and blink timing. Moss is the baseline.
  final double motionSpeed;

  Color get skinColor => Color(skin);
  Color get hairColor => Color(hair);
  Color get clothesColor => Color(clothes);
  Color get accentColor => Color(accent);

  static const moss = CharacterLook(
    id: 'moss',
    name: 'Moss',
    tagline: 'Daun hijau, tenang, dan sabar.',
    skin: 0xFFE8B98F,
    hair: 0xFF2F5D3A,
    clothes: 0xFF4F7A52,
    accent: 0xFF9CCB72,
    accessory: CharacterAccessory.leafCrown,
    motionSpeed: 1.0,
  );

  static const bara = CharacterLook(
    id: 'bara',
    name: 'Bara',
    tagline: 'Hangat seperti matahari pagi.',
    skin: 0xFFC98A5E,
    hair: 0xFF3A2418,
    clothes: 0xFFC0663F,
    accent: 0xFFF2B84B,
    accessory: CharacterAccessory.sunHat,
    motionSpeed: 1.35,
  );

  static const rintik = CharacterLook(
    id: 'rintik',
    name: 'Rintik',
    tagline: 'Sejuk seperti hujan pertama.',
    skin: 0xFF8D5A3B,
    hair: 0xFF1E2A38,
    clothes: 0xFF3F6E8C,
    accent: 0xFF8FD0E8,
    accessory: CharacterAccessory.rainCloud,
    motionSpeed: .82,
  );

  static const all = <CharacterLook>[moss, bara, rintik];

  static CharacterLook byId(String? id) =>
      all.firstWhere((look) => look.id == id, orElse: () => moss);

  /// A stable 0-2 index for compact persisted data.
  static int indexOf(String? id) {
    final index = all.indexWhere((look) => look.id == id);
    return index < 0 ? 0 : index;
  }
}
