import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// These settings affect the interface only; they are not sensor readings.
enum SkyChoice {
  automatic('Ikuti jam ponsel', null),
  dawn('Subuh', 5),
  morning('Pagi', 8),
  day('Siang', 12),
  evening('Sore', 16.5),
  night('Malam', 19.5),
  midnight('Tengah malam', 23),
  custom('Atur jam sendiri', null);

  const SkyChoice(this.label, this.exampleHour);

  final String label;
  final double? exampleHour;
}

class AppearanceSettings {
  const AppearanceSettings({
    this.themeMode = ThemeMode.system,
    this.sky = SkyChoice.automatic,
    this.manualMinute = 720,
  }) : assert(manualMinute >= 0 && manualMinute < 1440);

  final ThemeMode themeMode;
  final SkyChoice sky;
  final int manualMinute;

  AppearanceSettings copyWith({
    ThemeMode? themeMode,
    SkyChoice? sky,
    int? manualMinute,
  }) => AppearanceSettings(
    themeMode: themeMode ?? this.themeMode,
    sky: sky ?? this.sky,
    manualMinute: manualMinute ?? this.manualMinute,
  );

  static AppearanceSettings fromMap(Map<Object?, Object?>? map) {
    final theme = map?['theme'];
    final sky = map?['sky'];
    final minute = map?['manualMinute'];
    return AppearanceSettings(
      themeMode: ThemeMode.values.firstWhere(
        (value) => value.name == theme,
        orElse: () => ThemeMode.system,
      ),
      sky: SkyChoice.values.firstWhere(
        (value) => value.name == sky,
        orElse: () => SkyChoice.automatic,
      ),
      manualMinute: minute is int && minute >= 0 && minute < 1440
          ? minute
          : 720,
    );
  }

  Map<String, Object> toMap() => {
    'theme': themeMode.name,
    'sky': sky.name,
    'manualMinute': manualMinute,
  };
}

/// Android stores only these non-sensitive display preferences locally.
class AppearanceStore {
  const AppearanceStore();

  static const _channel = MethodChannel('moss/appearance');

  Future<AppearanceSettings> read() async {
    try {
      final data = await _channel.invokeMapMethod<Object?, Object?>('read');
      return AppearanceSettings.fromMap(data);
    } on PlatformException {
      return const AppearanceSettings();
    } on MissingPluginException {
      return const AppearanceSettings();
    }
  }

  Future<bool> write(AppearanceSettings settings) async {
    try {
      await _channel.invokeMethod<void>('write', settings.toMap());
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

class SkyAppearance {
  const SkyAppearance({
    required this.hour,
    required this.label,
    required this.top,
    required this.bottom,
    required this.sunOpacity,
    required this.moonOpacity,
    required this.starsOpacity,
  });

  final double hour;
  final String label;
  final Color top;
  final Color bottom;
  final double sunOpacity;
  final double moonOpacity;
  final double starsOpacity;

  static SkyAppearance resolve(
    SkyChoice choice,
    DateTime now, {
    int manualMinute = 720,
  }) {
    final hour = switch (choice) {
      SkyChoice.automatic => now.hour + now.minute / 60 + now.second / 3600,
      SkyChoice.custom => manualMinute.clamp(0, 1439) / 60,
      _ => choice.exampleHour!,
    };
    return atHour(hour);
  }

  static SkyAppearance atHour(double hour) {
    final time = hour.isFinite ? ((hour % 24) + 24) % 24 : 12.0;
    final frames = _frames;
    var index = 0;
    while (index < frames.length - 2 && time >= frames[index + 1].hour) {
      index++;
    }
    final from = frames[index];
    final to = frames[index + 1];
    final fraction = (time - from.hour) / (to.hour - from.hour);
    double lerp(double a, double b) => a + (b - a) * fraction;
    return SkyAppearance(
      hour: time,
      label: switch (time) {
        < 4.5 => 'Tengah malam',
        < 6.5 => 'Subuh',
        < 10 => 'Pagi',
        < 15 => 'Siang',
        < 18 => 'Sore',
        < 22 => 'Malam',
        _ => 'Tengah malam',
      },
      top: Color.lerp(from.top, to.top, fraction)!,
      bottom: Color.lerp(from.bottom, to.bottom, fraction)!,
      sunOpacity: lerp(from.sun, to.sun).clamp(0.0, 1.0),
      moonOpacity: lerp(from.moon, to.moon).clamp(0.0, 1.0),
      starsOpacity: lerp(from.stars, to.stars).clamp(0.0, 1.0),
    );
  }
}

class _SkyFrame {
  const _SkyFrame(
    this.hour,
    this.top,
    this.bottom,
    this.sun,
    this.moon,
    this.stars,
  );

  final double hour;
  final Color top;
  final Color bottom;
  final double sun;
  final double moon;
  final double stars;
}

const _frames = <_SkyFrame>[
  _SkyFrame(0, Color(0xFF101B35), Color(0xFF344365), 0, 1, .9),
  _SkyFrame(4.5, Color(0xFF465174), Color(0xFFD89887), .25, .55, .35),
  _SkyFrame(7, Color(0xFF8DC9D3), Color(0xFFF0DDC3), .9, 0, 0),
  _SkyFrame(12, Color(0xFF8AC8D8), Color(0xFFEAF0D5), 1, 0, 0),
  _SkyFrame(16, Color(0xFFE2A381), Color(0xFFF4D9AE), 1, 0, 0),
  _SkyFrame(18.5, Color(0xFF665B7E), Color(0xFFD18E7D), .3, .35, .2),
  _SkyFrame(20.5, Color(0xFF293851), Color(0xFF526484), 0, 1, .7),
  _SkyFrame(24, Color(0xFF101B35), Color(0xFF344365), 0, 1, .9),
];
