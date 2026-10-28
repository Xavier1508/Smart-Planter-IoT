import 'package:flutter/material.dart';

import 'appearance.dart';
import 'moss_app.dart';

class AppearancePanel extends StatelessWidget {
  const AppearancePanel({
    super.key,
    required this.settings,
    required this.storageUnavailable,
    required this.onThemeChanged,
    required this.onSkyChanged,
    required this.onManualTimeChanged,
  });

  final AppearanceSettings settings;
  final bool storageUnavailable;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<SkyChoice> onSkyChanged;
  final ValueChanged<int> onManualTimeChanged;

  Future<void> _pickTime(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: settings.manualMinute ~/ 60,
        minute: settings.manualMinute % 60,
      ),
      helpText: 'Pilih jam suasana Moss',
      cancelText: 'Batal',
      confirmText: 'Simpan',
      hourLabelText: 'Jam',
      minuteLabelText: 'Menit',
      errorInvalidText: 'Waktu tidak valid',
    );
    if (context.mounted && time != null) {
      onManualTimeChanged(time.hour * 60 + time.minute);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            Icons.palette_outlined,
            color: context.mossColors.primary,
            size: 21,
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Text(
              'Tampilan & suasana',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<ThemeMode>(
        key: ValueKey('theme-${settings.themeMode.name}'),
        initialValue: settings.themeMode,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Tema aplikasi'),
        items: const [
          DropdownMenuItem(
            value: ThemeMode.system,
            child: Text('Ikuti sistem'),
          ),
          DropdownMenuItem(value: ThemeMode.light, child: Text('Terang')),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('Gelap')),
        ],
        onChanged: (value) {
          if (value != null) onThemeChanged(value);
        },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<SkyChoice>(
        key: ValueKey('sky-${settings.sky.name}'),
        initialValue: settings.sky,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Suasana waktu Moss'),
        items: [
          for (final choice in SkyChoice.values)
            DropdownMenuItem(value: choice, child: Text(choice.label)),
        ],
        onChanged: (value) {
          if (value != null) onSkyChanged(value);
        },
      ),
      if (settings.sky == SkyChoice.custom) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('pick-moss-time'),
          onPressed: () => _pickTime(context),
          icon: const Icon(Icons.schedule_rounded),
          label: Text(
            'Jam pilihan: ${TimeOfDay(hour: settings.manualMinute ~/ 60, minute: settings.manualMinute % 60).format(context)}',
          ),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        settings.sky == SkyChoice.automatic
            ? 'Langit mengikuti jam lokal ponsel dan berubah perlahan.'
            : 'Suasana dipilih sendiri dan tidak mengubah jam ponsel.',
        style: TextStyle(
          color: context.mossColors.onSurfaceVariant,
          fontSize: 12,
          height: 1.4,
        ),
      ),
      if (storageUnavailable) ...[
        const SizedBox(height: 8),
        Text(
          'Pengaturan belum dapat disimpan di perangkat.',
          style: TextStyle(color: context.mossColors.error, fontSize: 12),
        ),
      ],
    ],
  );
}
