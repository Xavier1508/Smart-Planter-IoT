import 'package:flutter/material.dart';

import 'character_look.dart';
import 'moss_app.dart';
import 'plant_emotion.dart';
import 'plant_state.dart';
import 'profile_store.dart';

/// One phone-reception timestamp plus the decoded sample. The device uptime is
/// still the measurement clock; the local time is for the session timeline only.
class HistoryPoint {
  const HistoryPoint(this.at, this.state);

  final DateTime at;
  final PlantState state;
}

/// The 25-column CSV used by the append-only phone history and the single
/// local-only export. `emotion`/`confidence` are model outputs; they stay at
/// the end so a training script can drop them without touching the features.
String _sampleCountLabel(int count) {
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}k';
  }
  return '$count';
}

class HistoryCsv {
  const HistoryCsv._();

  static const header =
      'timestamp_utc,device_id,firmware_version,uptime_ms,soil_adc,'
      'soil_percent,water_adc,water_percent,water_observation_percent,'
      'water_empty,water_low,light_adc,light_percent,temperature_c,'
      'humidity_percent,uv_adc,uv_index,mq_adc,mq_gas_index,pump_cmd,'
      'pump_reason,light_cmd,light_reason,emotion,confidence';

  static String line({
    required DateTime now,
    required String deviceId,
    required int? firmwareVersion,
    required int? uptimeMs,
    required PlantState state,
    required EmotionReading emotion,
  }) {
    String field(Object? value) {
      final text = value?.toString() ?? '';
      if (text.contains(',') || text.contains('"') || text.contains('\n')) {
        return '"${text.replaceAll('"', '""')}"';
      }
      return text;
    }

    String flag(bool? value) => value == null ? '' : (value ? '1' : '0');

    return [
      field(now.toUtc().toIso8601String()),
      field(deviceId),
      field(firmwareVersion),
      field(uptimeMs),
      field(state.soilAdc),
      field(state.soilPercent),
      field(state.waterAdc),
      field(state.waterPercent),
      field(state.waterObservationPercent),
      flag(state.waterEmpty),
      flag(state.waterLow),
      field(state.lightAdc),
      field(state.lightPercent),
      field(state.temperatureC),
      field(state.humidityPercent),
      field(state.uvAdc),
      field(state.uvIndex),
      field(state.mqAdc),
      field(state.mqGasIndex),
      flag(state.pumpCommand),
      field(state.pumpReason),
      flag(state.lightCommand),
      field(state.lightReason),
      field(emotion.emotion.name),
      field(emotion.confidence.toStringAsFixed(3)),
    ].join(',');
  }

  static HistoryPoint? parse(String line) {
    final fields = _split(line);
    if (fields.length != 25) return null;
    final at = DateTime.tryParse(fields[0]);
    if (at == null) return null;
    int? number(int index) => int.tryParse(fields[index]);
    double? decimal(int index) => double.tryParse(fields[index]);
    bool? flag(int index) => fields[index] == '1'
        ? true
        : fields[index] == '0'
        ? false
        : null;
    String? text(int index) => fields[index].isEmpty ? null : fields[index];
    final state = PlantState(
      isSerialSnapshot: true,
      soilAdc: number(4),
      soilPercent: number(5),
      waterAdc: number(6),
      waterPercent: number(7),
      waterObservationPercent: number(8),
      waterEmpty: flag(9),
      waterLow: flag(10),
      lightAdc: number(11),
      lightPercent: number(12),
      temperatureC: decimal(13),
      humidityPercent: decimal(14),
      uvAdc: number(15),
      uvIndex: decimal(16),
      mqAdc: number(17),
      mqGasIndex: number(18),
      pumpCommand: flag(19),
      pumpReason: text(20),
      lightCommand: flag(21),
      lightReason: text(22),
    );
    return HistoryPoint(at.toLocal(), state);
  }

  static List<String> _split(String line) {
    final fields = <String>[];
    final current = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            current.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          current.write(char);
        }
      } else if (char == '"') {
        quoted = true;
      } else if (char == ',') {
        fields.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    fields.add(current.toString());
    return fields;
  }
}

/// Append-only local history. The CSV export is the full archive; the page
/// renders a bounded latest window so a long recording does not freeze the UI.
class JournalPage extends StatelessWidget {
  const JournalPage({
    super.key,
    required this.history,
    this.totalSamples = 0,
    required this.profile,
    required this.emotion,
    required this.onExport,
  });

  final List<HistoryPoint> history;
  final int totalSamples;
  final DeviceProfile profile;
  final EmotionReading emotion;
  final Future<void> Function() onExport;

  @override
  Widget build(BuildContext context) {
    final colors = context.mossColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Text(
          'JURNAL TANAMAN',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w800,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Text(
                'Riwayat',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Export CSV',
              onPressed: onExport,
              icon: const Icon(Icons.file_download_outlined),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _CharacterSummary(profile: profile, emotion: emotion),
        const SizedBox(height: 16),
        if (history.isEmpty)
          _EmptyHistory(
            message: 'Belum ada sampel tersimpan. Hubungkan perangkat dan biarkan aplikasi menerima data.',
          )
        else ...[
          _HistoryChart(history: history),
          const SizedBox(height: 10),
          Row(
            children: [
              _LegendDot(color: const Color(0xFF3F7D58), label: 'Tanah'),
              const SizedBox(width: 12),
              _LegendDot(color: const Color(0xFF3F7FA8), label: 'Air'),
              const SizedBox(width: 12),
              _LegendDot(color: const Color(0xFFB8862E), label: 'Cahaya'),
              const Spacer(),
              Text(
                '${_sampleCountLabel(totalSamples > 0 ? totalSamples : history.length)} sampel tersimpan',
                style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'TERBARU',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final point in history.reversed.take(14))
            _HistoryRow(point: point),
          const SizedBox(height: 8),
          Text(
            'Riwayat internal tetap saat app di-update, tetapi hilang jika app '
            'di-uninstall. Grafik menampilkan jendela sampel terbaru; total '
            'sampel terus bertambah dan CSV menyimpan seluruh data ke '
            'Downloads/Tunas.',
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          const _NumberGuide(),
        ],
      ],
    );
  }
}

class _NumberGuide extends StatelessWidget {
  const _NumberGuide();

  @override
  Widget build(BuildContext context) {
    final colors = context.mossColors;
    Widget line(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 10.5,
            height: 1.4,
            color: colors.onSurfaceVariant,
          ),
          children: [
            TextSpan(
              text: '$title: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: body),
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CARA BACA ANGKA',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 9),
          line(
            'Cahaya',
            'angka besar = kecerahan; baris kecil = ADC mentah. '
                '0 ADC = terang, 2100 ADC = gelap.',
          ),
          line(
            'UV',
            'angka besar = proxy 0-14 dari ADC; baris kecil = ADC mentah. '
                'Ini bukan UV index terkalibrasi.',
          ),
          line(
            'MQ135',
            'angka besar = indeks gas relatif 0-100 terhadap baseline; '
                'baris kecil = ADC dan tegangan pin.',
          ),
          line(
            'Riwayat',
            'total sampel terus bertambah; CSV menyimpan semua baris untuk '
                'analisis ML offline.',
          ),
        ],
      ),
    );
  }
}

class _CharacterSummary extends StatelessWidget {
  const _CharacterSummary({required this.profile, required this.emotion});

  final DeviceProfile profile;
  final EmotionReading emotion;

  @override
  Widget build(BuildContext context) {
    final colors = context.mossColors;
    final look = profile.look;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(
              look.accentColor.withValues(alpha: .18),
              colors.surfaceContainerLowest,
            ),
            colors.surfaceContainerLowest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: look.clothesColor,
              shape: BoxShape.circle,
              border: Border.all(color: look.accentColor, width: 2),
            ),
            child: Icon(
              switch (look.accessory) {
                CharacterAccessory.leafCrown => Icons.eco_rounded,
                CharacterAccessory.sunHat => Icons.wb_sunny_rounded,
                CharacterAccessory.rainCloud => Icons.water_drop_rounded,
              },
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.charName,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  profile.deviceName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  emotion.available
                      ? '${emotion.emotion.label} · ${emotion.confidencePercent}%'
                      : 'Menunggu perangkat',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: look.accentColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 38),
    decoration: BoxDecoration(
      color: context.mossColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.mossColors.outlineVariant),
    ),
    child: Column(
      children: [
        Icon(
          Icons.history_rounded,
          color: context.mossColors.primary,
          size: 42,
        ),
        const SizedBox(height: 16),
        const Text(
          'Belum ada riwayat',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.mossColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class _HistoryChart extends StatelessWidget {
  const _HistoryChart({required this.history});

  final List<HistoryPoint> history;

  @override
  Widget build(BuildContext context) => Container(
    height: 180,
    padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
    decoration: BoxDecoration(
      color: context.mossColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.mossColors.outlineVariant),
    ),
    child: CustomPaint(
      painter: _HistoryPainter(
        history: history.length > 60
            ? history.sublist(history.length - 60)
            : history,
        gridColor: context.mossColors.outlineVariant,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _HistoryPainter extends CustomPainter {
  const _HistoryPainter({required this.history, required this.gridColor});

  final List<HistoryPoint> history;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (history.isEmpty || size.width <= 0) return;
    _line(canvas, size, const Color(0xFF3F7D58), (state) => state.soilPercent);
    _line(
      canvas,
      size,
      const Color(0xFF3F7FA8),
      (state) => state.waterObservationPercent ?? state.waterPercent,
    );
    _line(canvas, size, const Color(0xFFB8862E), (state) => state.lightPercent);
  }

  void _line(
    Canvas canvas,
    Size size,
    Color color,
    int? Function(PlantState) valueOf,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final path = Path();
    var started = false;
    for (var i = 0; i < history.length; i++) {
      final value = valueOf(history[i].state);
      if (value == null) {
        started = false;
        continue;
      }
      final x = history.length == 1
          ? size.width / 2
          : size.width * i / (history.length - 1);
      final y = size.height * (1 - value.clamp(0, 100) / 100);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter oldDelegate) =>
      oldDelegate.history != history || oldDelegate.gridColor != gridColor;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10)),
    ],
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.point});

  final HistoryPoint point;

  @override
  Widget build(BuildContext context) {
    final time = point.at;
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    final state = point.state;
    final soil = state.soilPercent;
    final water = state.waterObservationPercent ?? state.waterPercent;
    final light = state.lightPercent;
    final temperature = state.temperatureC;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: context.mossColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.mossColors.outlineVariant),
      ),
      child: Row(
        children: [
          Text(
            stamp,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.mossColors.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tanah ${_value(soil)} · Air ${_value(water)} · '
              'Cahaya ${_value(light)}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          if (temperature != null)
            Text(
              '${temperature.toStringAsFixed(1)}°C',
              style: TextStyle(
                fontSize: 10,
                color: context.mossColors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  static String _value(int? value) => value == null ? '—' : '$value%';
}
