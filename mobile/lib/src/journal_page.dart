import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'moss_app.dart';
import 'plant_state.dart';

/// The chart is an explicitly labelled illustration, never stored as history.
class JournalPage extends StatefulWidget {
  const JournalPage({super.key, required this.demo, required this.scenario});

  final bool demo;
  final DemoScenario scenario;

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  bool _showSoil = true;

  List<double> get _points {
    if (!_showSoil) return const [25, 48, 72, 63, 38];
    return switch (widget.scenario) {
      DemoScenario.content => const [61, 58, 54, 66, 64],
      DemoScenario.thirsty => const [48, 40, 34, 28, 22],
      DemoScenario.airConcern => const [62, 60, 58, 57, 58],
    };
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
    children: [
      Text(
        'JURNAL TANAMAN',
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w800,
          color: context.mossColors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 7),
      const Text(
        'Riwayat',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Lihat perjalanan kecil tanamanmu di sini.',
        style: TextStyle(
          color: context.mossColors.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 22),
      if (!widget.demo)
        const _EmptyJournal()
      else ...[
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.mossColors.secondaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.science_outlined,
                color: context.mossColors.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RIWAYAT SIMULASI',
                      style: TextStyle(
                        color: context.mossColors.onSecondaryContainer,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Grafik dan aktivitas ini hanya contoh. Tidak ada data sensor yang disimpan.',
                      style: TextStyle(
                        color: context.mossColors.onSecondaryContainer,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.mossColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.mossColors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gambaran perubahan',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Pola ilustrasi, bukan pengukuran.',
                style: TextStyle(
                  color: context.mossColors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Tanah'),
                    selected: _showSoil,
                    onSelected: (_) => setState(() => _showSoil = true),
                  ),
                  ChoiceChip(
                    label: const Text('Cahaya'),
                    selected: !_showSoil,
                    onSelected: (_) => setState(() => _showSoil = false),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Semantics(
                key: const ValueKey('example-chart'),
                container: true,
                label:
                    'Grafik simulasi ${_showSoil ? 'tanah' : 'cahaya'}, bukan data sensor',
                child: SizedBox(
                  width: double.infinity,
                  height: 150,
                  child: CustomPaint(
                    painter: _ExampleChart(
                      points: _points,
                      color: _showSoil
                          ? context.mossColors.primary
                          : const Color(0xFFAB843A),
                      gridColor: context.mossColors.outlineVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Awal contoh',
                      style: TextStyle(
                        color: context.mossColors.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Akhir contoh',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: context.mossColors.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Contoh aktivitas',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        const _ExampleEvent(
          icon: Icons.water_drop_outlined,
          title: 'Pengingat perawatan',
          subtitle: 'Contoh tampilan, bukan notifikasi yang dikirim.',
        ),
        const _ExampleEvent(
          icon: Icons.eco_outlined,
          title: 'Moss mengenali perubahan',
          subtitle: 'Ekspresi mengikuti skenario simulasi.',
        ),
      ],
    ],
  );
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

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
          'Riwayat sensor nyata belum tersedia. Data simulasi tidak disimpan sebagai riwayat.',
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

class _ExampleEvent extends StatelessWidget {
  const _ExampleEvent({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: context.mossColors.surfaceContainerLowest,
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: Icon(icon, color: context.mossColors.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: Text(
        'CONTOH',
        style: TextStyle(
          color: context.mossColors.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _ExampleChart extends CustomPainter {
  const _ExampleChart({
    required this.points,
    required this.color,
    required this.gridColor,
  });
  final List<double> points;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;
    final path = Path();
    final dots = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final point = Offset(
        size.width * i / (points.length - 1),
        size.height * (1 - points[i].clamp(0, 100) / 100),
      );
      dots.add(point);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3;
    canvas.drawPath(path, line);
    final dot = Paint()..color = color;
    for (final point in dots) {
      canvas.drawCircle(point, math.min(4.0, size.width / 20), dot);
    }
  }

  @override
  bool shouldRepaint(covariant _ExampleChart oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor;
}
