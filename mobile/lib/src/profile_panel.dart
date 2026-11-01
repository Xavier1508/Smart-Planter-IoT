import 'package:flutter/material.dart';

import 'character_look.dart';
import 'character_picker.dart';
import 'local_wifi.dart';
import 'moss_app.dart';
import 'profile_store.dart';

/// Device registry and profile editor inside Settings. The list is the single
/// place where a device becomes active; connection state stays in Dashboard.
class ProfilePanel extends StatelessWidget {
  const ProfilePanel({
    super.key,
    required this.settings,
    required this.localSelected,
    required this.localStatus,
    required this.localMessage,
    required this.onConnect,
    required this.onDisconnect,
    required this.onSave,
    required this.onSelect,
    required this.onDelete,
    required this.render3d,
  });

  final ProfileSettings settings;
  final bool localSelected;
  final LocalWifiStatus localStatus;
  final String localMessage;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final Future<void> Function(DeviceProfile) onSave;
  final Future<void> Function(String) onSelect;
  final Future<void> Function(String) onDelete;
  final bool render3d;

  @override
  Widget build(BuildContext context) {
    final colors = context.mossColors;
    final active = settings.active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Perangkat & karakter',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${settings.devices.length}/6',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Satu profil = satu planter. Pilih perangkat aktif, lalu hubungkan. '
          'Alamat bisa diubah bila ESP32 berada di jaringan yang sama.',
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        for (final device in settings.devices)
          _DeviceTile(
            device: device,
            active: device.id == settings.activeId,
            selected: localSelected,
            onSelect: () => onSelect(device.id),
            onEdit: () => _editDevice(context, device),
            onDelete: settings.devices.length <= 1
                ? null
                : () => _confirmDelete(context, device),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: settings.devices.length >= 6
                  ? null
                  : () => _addDevice(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tambah perangkat'),
            ),
            if (localSelected)
              TextButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text('Putuskan'),
              )
            else
              FilledButton.tonalIcon(
                onPressed: localStatus == LocalWifiStatus.connecting
                    ? null
                    : onConnect,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Hubungkan'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          localSelected
              ? 'Aktif: ${active.charName} · ${active.host}:${active.port}. $localMessage'
              : 'Belum terhubung. Aktif: ${active.charName} · '
                    '${active.host}:${active.port}.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _addDevice(BuildContext context) async {
    final index = settings.devices.length;
    final look = CharacterLook.all[index % CharacterLook.all.length];
    final created = await showDialog<DeviceProfile>(
      context: context,
      builder: (context) => _ProfileDialog(
        title: 'Tambah perangkat',
        initial: DeviceProfile(
          id: 'planter-${DateTime.now().millisecondsSinceEpoch}',
          deviceName: 'Kebun ${index + 1}',
          charName: look.name,
          host: '192.168.4.1',
          port: 3333,
          characterId: look.id,
        ),
        render3d: render3d,
      ),
    );
    if (created != null) await onSave(created);
  }

  Future<void> _editDevice(BuildContext context, DeviceProfile device) async {
    final edited = await showDialog<DeviceProfile>(
      context: context,
      builder: (context) => _ProfileDialog(
        title: 'Edit profil',
        initial: device,
        render3d: render3d,
      ),
    );
    if (edited != null) await onSave(edited);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    DeviceProfile device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus perangkat?'),
        content: Text(
          '${device.charName} (${device.deviceName}) akan dihapus dari daftar. '
          'Riwayat sesi ini tidak disimpan permanen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onDelete(device.id);
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.active,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final DeviceProfile device;
  final bool active;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.mossColors;
    final look = device.look;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: active ? colors.primaryContainer : colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? look.accentColor : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: look.clothesColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  switch (look.accessory) {
                    CharacterAccessory.leafCrown => Icons.eco_rounded,
                    CharacterAccessory.sunHat => Icons.wb_sunny_rounded,
                    CharacterAccessory.rainCloud => Icons.water_drop_rounded,
                  },
                  color: Colors.white,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${device.charName} · ${device.deviceName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.host}:${device.port}'
                      '${active && selected ? ' · aktif' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: look.accentColor,
                ),
              IconButton(
                tooltip: 'Edit profil',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Hapus perangkat',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({
    required this.title,
    required this.initial,
    required this.render3d,
  });

  final String title;
  final DeviceProfile initial;
  final bool render3d;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _deviceName;
  late final TextEditingController _charName;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late CharacterLook _look;
  String? _error;

  @override
  void initState() {
    super.initState();
    _deviceName = TextEditingController(text: widget.initial.deviceName);
    _charName = TextEditingController(text: widget.initial.charName);
    _host = TextEditingController(text: widget.initial.host);
    _port = TextEditingController(text: '${widget.initial.port}');
    _look = widget.initial.look;
  }

  @override
  void dispose() {
    _deviceName.dispose();
    _charName.dispose();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _pickLook() async {
    final picked = await showCharacterPicker(
      context,
      current: _look,
      render3d: widget.render3d,
    );
    if (picked == null || !mounted) return;
    setState(() {
      final keepName = _charName.text.trim() != _look.name;
      _look = picked;
      if (!keepName) _charName.text = picked.name;
    });
  }

  void _save() {
    final deviceName = _deviceName.text.trim();
    final charName = _charName.text.trim();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (deviceName.isEmpty ||
        charName.isEmpty ||
        host.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535) {
      setState(() => _error = 'Nama, alamat, dan port harus valid.');
      return;
    }
    Navigator.of(context).pop(
      widget.initial.copyWith(
        deviceName: deviceName,
        charName: charName,
        host: host,
        port: port,
        characterId: _look.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _deviceName,
            textInputAction: TextInputAction.next,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Nama planter',
              hintText: 'Kebun balkon',
            ),
          ),
          TextField(
            controller: _charName,
            textInputAction: TextInputAction.next,
            maxLength: 30,
            decoration: const InputDecoration(
              labelText: 'Nama karakter',
              hintText: 'Moss',
            ),
          ),
          TextField(
            controller: _host,
            textInputAction: TextInputAction.next,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Alamat IP / host',
              hintText: '192.168.4.1',
            ),
          ),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Port',
              hintText: '3333',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _look.clothesColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_look.name} · ${_look.tagline}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              TextButton(onPressed: _pickLook, child: const Text('Pilih')),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Batal'),
      ),
      FilledButton(onPressed: _save, child: const Text('Simpan')),
    ],
  );
}
