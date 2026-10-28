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
  int? _selectedPoint;

  static const _lightPoints = <double>[25, 48, 72, 63, 38];

  List<double> get _soilPoints => switch (widget.scenario) {
    DemoScenario.content => const [61, 58, 54, 66, 64],
    DemoScenario.thirsty => const [48, 40, 34, 28, 22],
    DemoScenario.airConcern => const [62, 60, 58, 57, 58],
  };

  List<double> get _points => _showSoil ? _soilPoints : _lightPoints;

  String _pointDescription(int index) =>
      'Titik contoh ${index + 1}: ${_points[index].round()} persen';

  int get _nextPoint =>
      ((_selectedPoint ?? -1) + 1).clamp(0, _points.length - 1);

  int get _previousPoint =>
      ((_selectedPoint ?? 1) - 1).clamp(0, _points.length - 1);

  void _selectPoint(double x, double width) {
    if (width <= 0 || !x.isFinite) return;
    final index = (x / width * (_points.length - 1)).round().clamp(
      0,
      _points.length - 1,
    );
    if (index != _selectedPoint) setState(() => _selectedPoint = index);
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
                value: _selectedPoint == null
                    ? 'Belum ada titik dipilih'
                    : _pointDescription(_selectedPoint!),
                increasedValue: _pointDescription(_nextPoint),
                decreasedValue: _pointDescription(_previousPoint),
                onIncrease: () => setState(() => _selectedPoint = _nextPoint),
                onDecrease: () =>
                    setState(() => _selectedPoint = _previousPoint),
                child: SizedBox(
                  width: double.infinity,
                  height: 150,
                  child: LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTapDown: (details) => _selectPoint(
                        details.localPosition.dx,
                        constraints.maxWidth,
                      ),
                      onHorizontalDragUpdate: (details) => _selectPoint(
                        details.localPosition.dx,
                        constraints.maxWidth,
                      ),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: _showSoil ? 0.0 : 1.0),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 650),
                        curve: Curves.easeInOutCubic,
                        builder: (context, value, _) => CustomPaint(
                          painter: _ExampleChart(
                            points: [
                              for (var i = 0; i < _soilPoints.length; i++)
                                _soilPoints[i] +
                                    (_lightPoints[i] - _soilPoints[i]) * value,
                            ],
                            color: Color.lerp(
                              context.mossColors.primary,
                              const Color(0xFFAB843A),
                              value,
                            )!,
                            gridColor: context.mossColors.outlineVariant,
                            selectedPoint: _selectedPoint,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _selectedPoint == null
                    ? 'Sentuh grafik untuk melihat nilai contoh.'
                    : 'Titik contoh ${_selectedPoint! + 1}: ${_points[_selectedPoint!].round()}%',
                key: const ValueKey('example-chart-detail'),
                style: TextStyle(
                  color: context.mossColors.onSurfaceVariant,
                  fontSize: 12,
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
    required this.selectedPoint,
  });
  final List<double> points;
  final Color color;
  final Color gridColor;
  final int? selectedPoint;

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
        final previous = dots[i - 1];
        final midpoint = (previous.dx + point.dx) / 2;
        path.cubicTo(
          midpoint,
          previous.dy,
          midpoint,
          point.dy,
          point.dx,
          point.dy,
        );
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .22), color.withValues(alpha: .01)],
        ).createShader(Offset.zero & size),
    );
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
    final index = selectedPoint;
    if (index != null && index >= 0 && index < dots.length) {
      final selected = dots[index];
      canvas.drawLine(
        Offset(selected.dx, 0),
        Offset(selected.dx, size.height),
        Paint()
          ..color = color.withValues(alpha: .28)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        selected,
        7,
        Paint()..color = color.withValues(alpha: .22),
      );
      canvas.drawCircle(selected, 4, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _ExampleChart oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.selectedPoint != selectedPoint;
}
