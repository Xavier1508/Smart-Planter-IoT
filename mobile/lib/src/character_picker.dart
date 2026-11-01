import 'package:flutter/material.dart';

import 'appearance.dart';
import 'character_look.dart';
import 'moss_app.dart';
import 'moss_avatar.dart';
import 'moss_gaze.dart';
import 'plant_emotion.dart';
import 'plant_state.dart';

/// A game-like character picker: swipe between three looks, see the actual 3D
/// avatar for the selected page, then confirm. The caller persists the result.
Future<CharacterLook?> showCharacterPicker(
  BuildContext context, {
  required CharacterLook current,
  bool render3d = true,
}) => showModalBottomSheet<CharacterLook>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: context.mossColors.surface,
  builder: (context) => FractionallySizedBox(
    heightFactor: .86,
    child: _CharacterPicker(current: current, render3d: render3d),
  ),
);

class _CharacterPicker extends StatefulWidget {
  const _CharacterPicker({required this.current, required this.render3d});

  final CharacterLook current;
  final bool render3d;

  @override
  State<_CharacterPicker> createState() => _CharacterPickerState();
}

class _CharacterPickerState extends State<_CharacterPicker> {
  late final PageController _pages;
  late final MossGaze _gaze;
  late final MossAtmosphere _atmosphere;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = CharacterLook.indexOf(widget.current.id);
    _pages = PageController(initialPage: _index, viewportFraction: .86);
    _gaze = MossGaze();
    _atmosphere = MossAtmosphere(SkyAppearance.atHour(12));
  }

  @override
  void dispose() {
    _pages.dispose();
    _gaze.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = CharacterLook.all[_index];
    final colors = context.mossColors;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PILIH KARAKTER',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Teman tamanmu',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.7,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: CharacterLook.all.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) => _CharacterCard(
                look: CharacterLook.all[index],
                gaze: _gaze,
                atmosphere: _atmosphere,
                render3d: widget.render3d,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < CharacterLook.all.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _index
                        ? selected.accentColor
                        : colors.outlineVariant,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: Column(
              children: [
                Text(
                  selected.tagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(selected),
                    icon: const Icon(Icons.check_rounded),
                    label: Text('Gunakan ${selected.name}'),
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

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.look,
    required this.gaze,
    required this.atmosphere,
    required this.render3d,
  });

  final CharacterLook look;
  final MossGaze gaze;
  final MossAtmosphere atmosphere;
  final bool render3d;

  @override
  Widget build(BuildContext context) {
    final colors = context.mossColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Color.alphaBlend(
            look.accentColor.withValues(alpha: .10),
            colors.surfaceContainerLowest,
          ),
          border: Border.all(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    right: -26,
                    top: -20,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: look.accentColor.withValues(alpha: .13),
                      ),
                    ),
                  ),
                  Center(
                    child: SizedBox(
                      width: 230,
                      height: 300,
                      child: _AvatarPreview(
                        look: look,
                        gaze: gaze,
                        atmosphere: atmosphere,
                        render3d: render3d,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: look.accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      look.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                  ),
                  Text(
                    _temperament(look),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _temperament(CharacterLook look) => switch (look.id) {
    'bara' => 'ENERGIK',
    'rintik' => 'TENANG',
    _ => 'SABAR',
  };
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({
    required this.look,
    required this.gaze,
    required this.atmosphere,
    required this.render3d,
  });

  final CharacterLook look;
  final MossGaze gaze;
  final MossAtmosphere atmosphere;
  final bool render3d;

  @override
  Widget build(BuildContext context) {
    if (!render3d) {
      return Center(
        child: Container(
          width: 150,
          height: 190,
          decoration: BoxDecoration(
            color: look.clothesColor,
            borderRadius: BorderRadius.circular(70),
            border: Border.all(color: look.accentColor, width: 3),
          ),
          child: Icon(
            switch (look.accessory) {
              CharacterAccessory.leafCrown => Icons.eco_rounded,
              CharacterAccessory.sunHat => Icons.wb_sunny_rounded,
              CharacterAccessory.rainCloud => Icons.water_drop_rounded,
            },
            color: Colors.white,
            size: 64,
          ),
        ),
      );
    }
    return MossAvatar(
      key: ValueKey('preview-${look.id}'),
      mood: PlantMood.content,
      emotion: PlantEmotion.happy,
      look: look,
      sky: SkyAppearance.atHour(12),
      gaze: gaze,
      atmosphere: atmosphere,
    );
  }
}
