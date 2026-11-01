import 'dart:math';

/// Parses the same bounded CTRL syntax used by the local AP. Cloud mode reuses
/// the existing UI controls, but maps them to the atomic actuator RPC.
class CloudControlCommand {
  const CloudControlCommand({
    required this.actuator,
    required this.action,
    this.durationSeconds,
  });

  final String actuator;
  final String action;
  final int? durationSeconds;

  static CloudControlCommand? parse(String line) {
    if (line.length > 96) return null;
    final tokens = line.trim().split(RegExp(r'\s+'));
    if (tokens.isEmpty || tokens.first != 'CTRL') return null;
    String? actuator;
    String? action;
    int? duration;
    for (final token in tokens.skip(1)) {
      final separator = token.indexOf('=');
      if (separator <= 0) return null;
      final key = token.substring(0, separator);
      final value = token.substring(separator + 1);
      switch (key) {
        case 'pump':
        case 'light':
          if (actuator != null) return null;
          if (value != 'on' && value != 'off' && value != 'auto') return null;
          actuator = key;
          action = value;
        case 'dur':
          final parsed = int.tryParse(value);
          if (parsed == null || parsed < 1) return null;
          duration = parsed;
        case 'id':
          // Local control ids are not part of the cloud contract. The cloud
          // client generates a UUID that is reused on retry.
          if (int.tryParse(value) == null) return null;
        default:
          return null;
      }
    }
    if (actuator == null || action == null) return null;
    if (action == 'on') {
      if (duration == null) return null;
      if (actuator == 'pump' && (duration < 1 || duration > 30)) return null;
      if (actuator == 'light' && (duration < 1 || duration > 1800)) return null;
    }
    return CloudControlCommand(
      actuator: actuator,
      action: action,
      durationSeconds: action == 'on' ? duration : null,
    );
  }
}

/// RFC-4122 version-4 request id. The same id is reused across retries so a
/// timeout cannot create two physical pump commands.
String newCloudRequestId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  final text = bytes.map(hex).join();
  return '${text.substring(0, 8)}-${text.substring(8, 12)}-'
      '${text.substring(12, 16)}-${text.substring(16, 20)}-'
      '${text.substring(20)}';
}
