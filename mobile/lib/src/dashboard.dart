import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance.dart';
import 'appearance_panel.dart';
import 'app_version_panel.dart';
import 'character_look.dart';
import 'character_picker.dart';
import 'devices_page.dart';
import 'history_service.dart';
import 'journal_page.dart';
import 'local_wifi.dart';
import 'moss_app.dart';
import 'moss_avatar.dart';
import 'moss_gaze.dart';
import 'moss_sky.dart';
import 'notification_service.dart';
import 'plant_emotion.dart';
import 'plant_health.dart';
import 'plant_state.dart';
import 'plant_telemetry.dart';
import 'prediction_card.dart';
import 'profile_panel.dart';
import 'profile_store.dart';
import 'schedule.dart';
import 'top_notice.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key,
    required this.render3d,
    required this.gaze,
    required this.atmosphere,
    this.telemetry,
    this.initialSerialJson = '',
    this.cloudSettings,
    this.localWifi,
    this.autoConnectLocal = true,
    required this.appearance,
    required this.sky,
    required this.storageUnavailable,
    required this.onThemeChanged,
    required this.onSkyChanged,
    required this.onManualTimeChanged,
  });

  final bool render3d;
  final MossGaze gaze;
  final MossAtmosphere atmosphere;
  final Stream<PlantTelemetry>? telemetry;
  final String initialSerialJson;
  final Widget? cloudSettings;
  final LocalWifiController? localWifi;
  final bool autoConnectLocal;
  final AppearanceSettings appearance;
  final SkyAppearance sky;
  final bool storageUnavailable;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<SkyChoice> onSkyChanged;
  final ValueChanged<int> onManualTimeChanged;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  static const _readingMaxAge = Duration(minutes: 2);

  var _page = 0;
  var _liveState = const PlantState.waiting();
  PlantState? _serialSnapshot;
  String? _serialMessage;
  var _sourceNotice = 'Menunggu data sensor.';
  DateTime? _lastRecordedAt;
  int? _lastSequence;
  StreamSubscription<PlantTelemetry>? _subscription;
  Timer? _expiry;
  late LocalWifiController _localWifi;
  late bool _ownsLocalWifi;
  StreamSubscription<void>? _localWifiChanges;
  bool _useLocalWifi = false;
  final ScheduleStore _scheduleStore = const ScheduleStore();
  List<ScheduleEntry> _schedules = const [];
  List<RunningSchedule> _runningSchedules = const [];
  Timer? _scheduleTimer;
  bool _scheduleBusy = false;
  final ProfileStore _profileStore = const ProfileStore();
  ProfileSettings _profiles = ProfileSettings.defaults;
  PlantHealthModel? _emotionModel;
  List<HistoryPoint> _history = [];
  int? _lastHistoryUptime;
  final HistoryService _historyService = const HistoryService();
  final NotificationService _notifications = const NotificationService();
  LocalWifiStatus _lastNoticeStatus = LocalWifiStatus.disconnected;
  DateTime? _lastWaterAlertAt;
  DateTime? _lastPredictionScheduleAt;
  PlantEmotion? _lastInsightEmotion;
  StreamSubscription<NotificationPayload>? _notificationSub;

  @override
  void initState() {
    super.initState();
    _attachLocalWifi(widget.localWifi);
    _listenToTelemetry();
    _loadSchedules();
    _loadProfiles();
    _loadEmotionModel();
    _notificationSub = _notifications.taps.listen(_handleNotificationPayload);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_notifications.requestPermission());
        unawaited(_notifications.cancel(NotificationService.predictionId));
        unawaited(_handleNotificationLaunch());
      }
    });
    _scheduleTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_runSchedules()),
    );
    if (widget.initialSerialJson.isNotEmpty) {
      try {
        _serialSnapshot = PlantState.fromSerial(
          SerialSensorSnapshot.parse(widget.initialSerialJson),
        );
      } catch (_) {
        _sourceNotice = 'Snapshot serial tidak valid; menunggu sumber data.';
      }
    } else if (widget.autoConnectLocal) {
      _useLocalWifi = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _useLocalWifi) unawaited(_localWifi.connect());
      });
    }
  }

  @override
  void didUpdateWidget(covariant Dashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.telemetry != widget.telemetry) _listenToTelemetry();
    if (oldWidget.localWifi != widget.localWifi) {
      final previous = _localWifiChanges;
      if (previous != null) unawaited(previous.cancel());
      if (_ownsLocalWifi) _localWifi.dispose();
      _useLocalWifi = false;
      _attachLocalWifi(widget.localWifi);
    }
  }

  void _attachLocalWifi(LocalWifiController? controller) {
    _ownsLocalWifi = controller == null;
    _localWifi =
        controller ??
        LocalWifiController(
          address: _profiles.active.host,
          port: _profiles.active.port,
        );
    _localWifiChanges = _localWifi.changes.listen((_) => _onLocalWifiChanged());
  }

  Future<void> _loadProfiles() async {
    final loaded = await _profileStore.read();
    if (!mounted) return;
    final previous = _profiles.active;
    final changed =
        loaded.active.host != previous.host ||
        loaded.active.port != previous.port;
    setState(() => _profiles = loaded);
    if (widget.localWifi == null && changed) {
      final wasWanted = _useLocalWifi;
      _rebindLocalWifi();
      if (wasWanted) unawaited(_localWifi.connect());
    }
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    final device = _profiles.active;
    final rows = await _historyService.readTail(
      deviceId: device.id,
      limit: 240,
    );
    if (!mounted) return;
    final stored = rows
        .map(HistoryCsv.parse)
        .whereType<HistoryPoint>()
        .toList(growable: false);
    // Merge instead of replacing. A slow or empty native read must never make
    // samples that are already visible in this session disappear.
    final merged = <String, HistoryPoint>{
      for (final point in _history) point.at.toIso8601String(): point,
      for (final point in stored) point.at.toIso8601String(): point,
    }.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    final tail = merged.length > 240
        ? merged.sublist(merged.length - 240)
        : merged;
    setState(() => _history = tail);
  }

  Future<void> _loadEmotionModel() async {
    try {
      final raw = await rootBundle.loadString('assets/ml/plant-health.json');
      final model = PlantHealthModel.parse(raw);
      if (mounted) setState(() => _emotionModel = model);
    } catch (_) {
      // The threshold rules still drive the presentation if the asset is
      // unavailable; no invented model output is shown.
    }
  }

  void _rebindLocalWifi() {
    final previous = _localWifiChanges;
    if (previous != null) unawaited(previous.cancel());
    if (_ownsLocalWifi) _localWifi.dispose();
    final active = _profiles.active;
    _ownsLocalWifi = true;
    _localWifi = LocalWifiController(address: active.host, port: active.port);
    _localWifiChanges = _localWifi.changes.listen((_) => _onLocalWifiChanged());
    _history.clear();
    _lastHistoryUptime = null;
    _runningSchedules = const [];
  }

  void _onLocalWifiChanged() {
    final status = _localWifi.status;
    final previousStatus = _lastNoticeStatus;
    _lastNoticeStatus = status;
    if (status == LocalWifiStatus.live &&
        previousStatus != LocalWifiStatus.live) {
      // The first live frame after a reconnect is a good moment to merge any
      // rows written while this page was not watching the stream.
      unawaited(_loadHistory());
    }
    if (status == LocalWifiStatus.disconnected &&
        previousStatus != LocalWifiStatus.disconnected &&
        _useLocalWifi &&
        mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showTopNotice(
          context,
          title: 'Perangkat terputus',
          message:
              'Tidak dapat terhubung ke ${_profiles.active.charName}. '
              'Periksa jaringan perangkat lalu coba lagi.',
          icon: Icons.wifi_off_rounded,
        );
      });
    }

    final sample = _localWifi.snapshot;
    final uptime = sample?.uptimeMs;
    if (sample != null && uptime != null && uptime != _lastHistoryUptime) {
      _lastHistoryUptime = uptime;
      final now = DateTime.now();
      final state = PlantState.fromLocalWifi(
        sample,
        mqAverageAdc: _localWifi.mqAverageAdc,
        mqAverageSamples: _localWifi.mqAverageSamples,
        mqTrend: _localWifi.mqTrend,
        mqGasIndex: _localWifi.mqGasIndex,
        mqGasStatus: _localWifi.mqGasStatus,
        mqGasBaselineMv: _localWifi.mqGasBaselineMv,
      );
      _history.add(HistoryPoint(now, state));
      if (_history.length > 240) _history.removeAt(0);
      final emotion = PlantEmotionEngine(_emotionModel)
          .evaluate(state, recent: _recentStates());
      _maybeNotifyLowWater(state, now);
      _maybeShowInsight(now, emotion);
      unawaited(
        _historyService.append(
          deviceId: _profiles.active.id,
          header: HistoryCsv.header,
          line: HistoryCsv.line(
            now: now,
            deviceId: _profiles.active.id,
            firmwareVersion: sample.firmwareVersion,
            uptimeMs: sample.uptimeMs,
            state: state,
            emotion: emotion,
          ),
        ),
      );
    }
    if (mounted) setState(() {});
  }

  List<PlantState> _recentStates() =>
      _history.length > PlantEmotionEngine.window
      ? _history
            .sublist(_history.length - PlantEmotionEngine.window)
            .map((point) => point.state)
            .toList()
      : _history.map((point) => point.state).toList();

  Future<void> _handleNotificationLaunch() async {
    final payload = await _notifications.takeLaunch();
    if (payload != null && mounted) _handleNotificationPayload(payload);
  }

  void _handleNotificationPayload(NotificationPayload payload) {
    if (!mounted) return;
    final page = switch (payload.route) {
      'devices' => 2,
      'journal' => 1,
      _ => 0,
    };
    setState(() => _page = page);
    if (payload.body.trim().isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (payload.route == 'home') {
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(payload.title),
            content: SingleChildScrollView(child: Text(payload.body)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Tutup'),
              ),
            ],
          ),
        );
      } else {
        showTopNotice(
          context,
          title: payload.title,
          message: payload.body,
          icon: Icons.notifications_active_outlined,
          duration: const Duration(seconds: 6),
        );
      }
    });
  }

  void _maybeNotifyLowWater(PlantState state, DateTime now) {
    final level = state.waterLevel;
    final empty = level == WaterLevel.empty;
    final low = empty || level == WaterLevel.low || state.waterLow == true;
    if (!low) return;
    final last = _lastWaterAlertAt;
    if (last != null && now.difference(last) < const Duration(minutes: 30)) {
      return;
    }
    _lastWaterAlertAt = now;
    final label = switch (level) {
      WaterLevel.empty => 'kosong',
      WaterLevel.low => 'rendah',
      WaterLevel.medium => 'medium',
      WaterLevel.full => 'penuh',
      null => state.waterLow == true ? 'rendah' : 'belum terbaca',
    };
    unawaited(
      _notifications.show(
        id: NotificationService.waterAlertId,
        title: empty ? 'Air penampung habis' : 'Air penampung hampir habis',
        body: empty
            ? 'Level air kosong. Isi ulang penampung.'
            : 'Level air $label. Isi ulang penampung.',
        channel: 'tunas_alerts',
        route: 'devices',
        payload: empty
            ? 'Air penampung kosong. Isi ulang penampung.'
            : 'Air penampung $label. Isi ulang penampung.',
      ),
    );
  }

  void _maybeShowInsight(DateTime now, EmotionReading emotion) {
    if (!emotion.available) return;
    final escalated =
        emotion.emotion == PlantEmotion.alert &&
        _lastInsightEmotion != PlantEmotion.alert;
    final last = _lastPredictionScheduleAt;
    if (!escalated &&
        last != null &&
        now.difference(last) < const Duration(minutes: 5)) {
      return;
    }
    _lastPredictionScheduleAt = now;
    _lastInsightEmotion = emotion.emotion;
    final body = '${emotion.signal} ${emotion.prediction}'.trim();
    unawaited(
      _notifications.show(
        id: NotificationService.insightId,
        title: 'Tunas · ${emotion.emotion.label}',
        body: body,
        channel: emotion.emotion == PlantEmotion.alert
            ? 'tunas_alerts'
            : 'tunas_predictions',
        route: 'home',
        payload: body,
      ),
    );
  }

  Future<void> _saveProfile(DeviceProfile profile) async {
    final previous = _profiles.active;
    setState(() => _profiles = _profiles.upsert(profile));
    await _profileStore.write(_profiles);
    if (widget.localWifi == null &&
        profile.id == _profiles.activeId &&
        (profile.host != previous.host || profile.port != previous.port)) {
      final wasWanted = _useLocalWifi;
      _rebindLocalWifi();
      unawaited(_loadHistory());
      if (wasWanted) unawaited(_localWifi.connect());
    }
  }

  Future<void> _selectProfile(String id) async {
    if (id == _profiles.activeId) return;
    setState(() {
      _profiles = _profiles.copyWith(activeId: id);
      _serialSnapshot = null;
      _history.clear();
      _lastHistoryUptime = null;
    });
    await _profileStore.write(_profiles);
    if (widget.localWifi == null) {
      final wasWanted = _useLocalWifi;
      _rebindLocalWifi();
      if (wasWanted) unawaited(_localWifi.connect());
    }
    unawaited(_loadHistory());
  }

  Future<void> _deleteProfile(String id) async {
    if (_profiles.devices.length <= 1) return;
    final wasActive = id == _profiles.activeId;
    setState(() => _profiles = _profiles.remove(id));
    await _profileStore.write(_profiles);
    if (wasActive && widget.localWifi == null) {
      _rebindLocalWifi();
      if (_useLocalWifi) unawaited(_localWifi.connect());
      unawaited(_loadHistory());
    }
  }

  Future<void> _pickCharacter() async {
    final active = _profiles.active;
    final selected = await showCharacterPicker(
      context,
      current: active.look,
      render3d: widget.render3d,
    );
    if (selected == null || !mounted) return;
    final keepName = active.charName != active.look.name;
    await _saveProfile(
      active.copyWith(
        characterId: selected.id,
        charName: keepName ? active.charName : selected.name,
      ),
    );
  }

  Future<void> _requestNotificationPermission() async {
    await _notifications.requestPermission();
  }

  Future<void> _testNotification() async {
    await _notifications.requestPermission();
    await _notifications.show(
      id: 4199,
      title: 'Tunas siap memberi kabar',
      body:
          'Notifikasi HP aktif. Peringatan air rendah dan prediksi berkala '
          'akan muncul di sini.',
      channel: 'tunas_alerts',
    );
  }

  Future<void> _exportHistory() async {
    final path = await _historyService.export(deviceId: _profiles.active.id);
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      showTopNotice(
        context,
        title: 'Export CSV gagal',
        message: 'Belum ada data tersimpan untuk perangkat ini.',
        icon: Icons.error_outline_rounded,
      );
    } else {
      showTopNotice(
        context,
        title: 'CSV tersimpan',
        message: path,
        icon: Icons.file_download_done_rounded,
      );
    }
  }

  void _connectLocalWifi() {
    setState(() {
      _useLocalWifi = true;
      _serialSnapshot = null;
    });
    unawaited(_localWifi.connect());
  }

  void _disconnectLocalWifi() {
    setState(() => _useLocalWifi = false);
    _localWifi.disconnect();
  }

  int _nextControlId = 1;

  int _controlId() => _nextControlId++;

  Future<bool> _sendControl(String line) {
    if (!_useLocalWifi) return Future<bool>.value(false);
    return _localWifi.sendControlCommand(line);
  }

  Future<void> _refresh() async {
    if (_useLocalWifi) {
      await _localWifi.connect();
    } else if (widget.telemetry == null && _serialSnapshot == null) {
      _listenToTelemetry();
    }
    if (mounted) setState(() {});
  }

  void _listenToTelemetry() {
    final previous = _subscription;
    if (previous != null) unawaited(previous.cancel());
    _subscription = null;
    _expiry?.cancel();
    _lastRecordedAt = null;
    _lastSequence = null;
    _liveState = const PlantState.waiting();
    final source = widget.telemetry;
    _sourceNotice = source == null
        ? 'Menunggu data sensor.'
        : 'Menunggu pembacaan sensor.';
    if (source == null) return;
    _subscription = source.listen(
      _acceptReading,
      onError: (Object _, StackTrace _) => _disconnect(),
      onDone: _disconnect,
    );
  }

  void _acceptReading(PlantTelemetry reading) {
    if (!mounted) return;
    final now = DateTime.now();
    if (!reading.isFreshAt(now, maxAge: _readingMaxAge)) {
      if (!_liveState.isLive) {
        setState(() {
          _sourceNotice = 'Pembacaan terlalu lama atau waktu tidak sesuai.';
        });
      }
      return;
    }
    final previous = _lastRecordedAt;
    if (previous != null && reading.recordedAt.isBefore(previous)) return;
    if (previous != null &&
        reading.recordedAt.isAtSameMomentAs(previous) &&
        _lastSequence != null &&
        (reading.sequence == null ||
            reading.sequence! < _lastSequence! ||
            (reading.sequence == _lastSequence && _liveState.isLive))) {
      return;
    }
    final next = PlantState.fromTelemetry(reading);
    if (!next.hasSensorData) {
      _expiry?.cancel();
      _lastRecordedAt = reading.recordedAt;
      _lastSequence = reading.sequence;
      setState(() {
        _liveState = const PlantState.waiting();
        _sourceNotice = 'Menunggu pembacaan sensor yang valid.';
      });
      return;
    }

    _expiry?.cancel();
    _lastRecordedAt = reading.recordedAt;
    _lastSequence = reading.sequence;
    setState(() {
      _liveState = next;
      _sourceNotice = 'Pembacaan sensor terbaru.';
    });
    final remaining = reading.recordedAt.add(_readingMaxAge).difference(now);
    _expiry = Timer(remaining, () {
      if (!mounted) return;
      setState(() {
        _liveState = const PlantState.waiting();
        _sourceNotice = 'Data sensor sudah lama; menunggu pembaruan.';
      });
    });
  }

  void _disconnect() {
    if (!mounted) return;
    _expiry?.cancel();
    setState(() {
      _liveState = const PlantState.waiting();
      _sourceNotice = 'Koneksi data terputus.';
    });
  }

  Future<void> _importSerialSnapshot() async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboard?.text;
      if (text == null) throw const FormatException();
      final snapshot = SerialSensorSnapshot.parse(text.trim());
      if (!mounted) return;
      _localWifi.disconnect();
      setState(() {
        _useLocalWifi = false;
        _serialSnapshot = PlantState.fromSerial(snapshot);
        _serialMessage = null;
        _page = 0;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _serialMessage = 'Salin satu baris JSON sample dari monitor serial.';
        });
      }
    }
  }

  void _clearSerialSnapshot() => setState(() {
    _serialSnapshot = null;
    _serialMessage = null;
  });

  Future<void> _loadSchedules() async {
    final loaded = await _scheduleStore.read();
    if (!mounted) return;
    setState(() {
      _schedules = List<ScheduleEntry>.of(loaded)
        ..sort((a, b) => a.at.compareTo(b.at));
    });
  }

  List<ScheduleEntry> _orderedSchedules(Iterable<ScheduleEntry> entries) {
    final next = List<ScheduleEntry>.of(entries)
      ..sort((a, b) {
        final byTime = a.at.compareTo(b.at);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return next;
  }

  Future<void> _addSchedule(ScheduleEntry entry) async {
    final next = _orderedSchedules([..._schedules, entry]);
    setState(() => _schedules = next);
    // Persisting must not delay an immediate action. The store catches its own
    // platform errors, so the in-memory schedule stays authoritative for this
    // session.
    unawaited(_scheduleStore.write(next));
    // "Sekarang" must not wait for the next one-second timer tick.
    if (entry.immediate) await _runSchedules();
  }

  Future<void> _deleteSchedule(int id) async {
    final next = _schedules.where((entry) => entry.id != id).toList();
    setState(() => _schedules = next);
    unawaited(_scheduleStore.write(next));
  }

  Future<void> _stopRunningSchedule(RunningSchedule running) async {
    if (_scheduleBusy) return;
    _scheduleBusy = true;
    try {
      final id = _controlId();
      final command = running.entry.target == 'pump'
          ? 'CTRL pump=off id=$id'
          : 'CTRL light=off id=$id';
      final sent = await _localWifi.sendControlCommand(command);
      if (!sent || !mounted) return;
      setState(() {
        _runningSchedules = _runningSchedules
            .where((item) => item.entry.id != running.entry.id)
            .toList();
      });
    } finally {
      _scheduleBusy = false;
    }
  }

  Future<void> _runSchedules() async {
    // One clock read per tick. Due-time comparison, command start and the
    // countdown all use the same instant, so two jobs can never race each
    // other inside one scheduler pass.
    final now = DateTime.now();
    final stillRunning = _runningSchedules
        .where((running) => !running.expired(now))
        .toList(growable: false);
    if (stillRunning.length != _runningSchedules.length && mounted) {
      setState(() => _runningSchedules = stillRunning);
    }
    if (_scheduleBusy || _schedules.isEmpty) return;

    final due = _orderedSchedules(
      _schedules.where((entry) => !entry.at.isAfter(now)),
    );
    if (due.isEmpty) return;
    final entry = due.first;

    // A calendar job that could not run while the phone was offline is
    // discarded once it is clearly stale; an immediate job may wait for the
    // next connection instead.
    if (!entry.immediate &&
        now.difference(entry.at) > const Duration(minutes: 2)) {
      await _deleteSchedule(entry.id);
      return;
    }
    if (!_useLocalWifi ||
        _localWifi.status != LocalWifiStatus.live ||
        _localWifi.snapshot == null) {
      return;
    }

    _scheduleBusy = true;
    try {
      final sent = await _localWifi.sendControlCommand(entry.command);
      if (!sent) return;
      await _deleteSchedule(entry.id);
      if (entry.on && entry.durationSeconds > 0) {
        final running = RunningSchedule(
          entry: entry,
          startedAt: now,
          endsAt: now.add(Duration(seconds: entry.durationSeconds)),
        );
        if (mounted) {
          setState(() => _runningSchedules = [..._runningSchedules, running]);
        }
      }
    } finally {
      _scheduleBusy = false;
    }
  }

  @override
  void dispose() {
    dismissTopNotice();
    _expiry?.cancel();
    _scheduleTimer?.cancel();
    final localChanges = _localWifiChanges;
    if (localChanges != null) unawaited(localChanges.cancel());
    if (_ownsLocalWifi) _localWifi.dispose();
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    final notificationSub = _notificationSub;
    if (notificationSub != null) unawaited(notificationSub.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localSample = _localWifi.snapshot;
    final state = _useLocalWifi
        ? (localSample == null
              ? const PlantState.waiting()
              : PlantState.fromLocalWifi(
                  localSample,
                  live: _localWifi.status == LocalWifiStatus.live,
                  mqAverageAdc: _localWifi.mqAverageAdc,
                  mqAverageSamples: _localWifi.mqAverageSamples,
                  mqTrend: _localWifi.mqTrend,
                  mqGasIndex: _localWifi.mqGasIndex,
                  mqGasStatus: _localWifi.mqGasStatus,
                  mqGasBaselineMv: _localWifi.mqGasBaselineMv,
                ))
        : (_serialSnapshot ?? _liveState);
    final active = _profiles.active;
    final recent = _history.length > PlantEmotionEngine.window
        ? _history
              .sublist(_history.length - PlantEmotionEngine.window)
              .map((point) => point.state)
              .toList()
        : _history.map((point) => point.state).toList();
    final emotion = PlantEmotionEngine(_emotionModel)
        .evaluate(state, recent: recent);
    return Scaffold(
      body: SafeArea(
        child: switch (_page) {
          0 => _Home(
            state: state,
            render3d: widget.render3d,
            gaze: widget.gaze,
            atmosphere: widget.atmosphere,
            sourceNotice: state.isSerialSnapshot
                ? 'Data serial tersimpan; waktu ukur tidak diketahui. Bukan live.'
                : _useLocalWifi
                ? _localWifi.message
                : _sourceNotice,
            localSelected: _useLocalWifi,
            localStatus: _localWifi.status,
            sky: widget.sky,
            automaticSky: widget.appearance.sky == SkyChoice.automatic,
            selectedSky: widget.appearance.sky,
            onSkyChanged: widget.onSkyChanged,
            onRefresh: _refresh,
            profile: active,
            emotion: emotion,
            onPickCharacter: _pickCharacter,
          ),
          1 => JournalPage(
            history: List<HistoryPoint>.unmodifiable(_history),
            profile: active,
            emotion: emotion,
            onExport: _exportHistory,
          ),
          2 => DevicesPage(
            state: state,
            localSelected: _useLocalWifi,
            localStatus: _localWifi.status,
            onCommand: _useLocalWifi ? _sendControl : null,
            controlId: _controlId,
            schedules: _schedules,
            runningSchedules: _runningSchedules,
            onAddSchedule: _addSchedule,
            onDeleteSchedule: _deleteSchedule,
            onStopRunningSchedule: _stopRunningSchedule,
          ),
          _ => _SettingsPage(
            cloudSettings: widget.cloudSettings,
            serialMessage: _serialMessage,
            hasSerialSnapshot: _serialSnapshot != null,
            onImportSerial: _importSerialSnapshot,
            onClearSerial: _clearSerialSnapshot,
            localSelected: _useLocalWifi,
            localStatus: _localWifi.status,
            localMessage: _localWifi.message,
            onConnectLocal: _connectLocalWifi,
            onDisconnectLocal: _disconnectLocalWifi,
            appearance: widget.appearance,
            storageUnavailable: widget.storageUnavailable,
            onThemeChanged: widget.onThemeChanged,
            onSkyChanged: widget.onSkyChanged,
            onManualTimeChanged: widget.onManualTimeChanged,
            profiles: _profiles,
            onSelectProfile: _selectProfile,
            onSaveProfile: _saveProfile,
            onDeleteProfile: _deleteProfile,
            render3d: widget.render3d,
            onTestNotification: _testNotification,
            onRequestNotificationPermission: _requestNotificationPermission,
          ),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (index) => setState(() => _page = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.spa_outlined),
            selectedIcon: Icon(Icons.spa),
            label: 'Hari ini',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Riwayat',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors),
            label: 'Perangkat',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Pengaturan',
          ),
        ],
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({
    required this.state,
    required this.render3d,
    required this.gaze,
    required this.atmosphere,
    required this.sourceNotice,
    required this.localSelected,
    required this.localStatus,
    required this.sky,
    required this.automaticSky,
    required this.selectedSky,
    required this.onSkyChanged,
    required this.onRefresh,
    required this.profile,
    required this.emotion,
    required this.onPickCharacter,
  });

  final PlantState state;
  final bool render3d;
  final MossGaze gaze;
  final MossAtmosphere atmosphere;
  final String sourceNotice;
  final bool localSelected;
  final LocalWifiStatus localStatus;
  final SkyAppearance sky;
  final bool automaticSky;
  final SkyChoice selectedSky;
  final ValueChanged<SkyChoice> onSkyChanged;
  final Future<void> Function() onRefresh;
  final DeviceProfile profile;
  final EmotionReading emotion;
  final VoidCallback onPickCharacter;

  bool get _deviceConnected =>
      state.isLive ||
      state.isSerialSnapshot ||
      localStatus == LocalWifiStatus.live ||
      localStatus == LocalWifiStatus.waiting ||
      localStatus == LocalWifiStatus.connecting;

  String _percent(int? value) => value == null ? '—' : '$value%';

  String _lockoutText(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (minutes <= 0) return '$rest dtk';
    return rest == 0 ? '$minutes mnt' : '$minutes mnt $rest dtk';
  }

  void _stepSky({required bool next}) =>
      onSkyChanged(SkyChoice.step(selectedSky, sky.hour, next: next));

  @override
  Widget build(BuildContext context) {
    final mood = state.mood;
    final skyInk = MossSky.foregroundFor(sky.bottom);
    final skyHeaderInk = MossSky.foregroundFor(sky.top);
    final mutedColor = context.mossColors.onSurfaceVariant;
    final tint = Color.lerp(
      const Color(0x19233665),
      const Color(0x09FFD38C),
      sky.sunOpacity,
    )!;
    final transition = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 1200);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SMART PLANTER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.0,
                              color: mutedColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ruang ${profile.charName}',
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _deviceConnected
                                ? profile.deviceName
                                : 'Belum ada perangkat terhubung',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusPill(
                      live: state.isLive,
                      snapshot: state.isSerialSnapshot,
                      connecting:
                          localSelected &&
                          (localStatus == LocalWifiStatus.connecting ||
                              localStatus == LocalWifiStatus.waiting),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Notice(live: state.isLive, sourceNotice: sourceNotice),
                if ((state.pumpCooldownSeconds ?? 0) > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3D6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 18,
                          color: Color(0xFF8A5A12),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.pumpRuntimeLockout == true
                                ? 'Pompa otomatis dikunci '
                                      '${_lockoutText(state.pumpCooldownSeconds!)} '
                                      'setelah batas 5 menit. Manual ON tetap '
                                      'bisa 1–30 detik.'
                                : 'Pompa jeda '
                                      '${_lockoutText(state.pumpCooldownSeconds!)} '
                                      'sebelum otomatis menyala lagi.',
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: Color(0xFF6B4610),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                MossSky(
                  sky: sky,
                  gaze: gaze,
                  atmosphere: atmosphere,
                  onSwipe: (next) => _stepSky(next: next),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                        child: Row(
                          children: [
                            Icon(Icons.eco_outlined, color: skyInk, size: 17),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                emotion.available
                                    ? emotion.emotion.label.toUpperCase()
                                    : state.moodLabel.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: skyHeaderInk,
                                ),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                '${sky.label.toUpperCase()} · ${automaticSky ? 'JAM HP' : 'PILIHAN'}',
                                textAlign: TextAlign.end,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: .6,
                                  color: skyHeaderInk,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 235,
                        width: double.infinity,
                        child: TweenAnimationBuilder<Color?>(
                          tween: ColorTween(end: tint),
                          duration: transition,
                          builder: (context, color, child) => ColorFiltered(
                            colorFilter: ColorFilter.mode(
                              color!,
                              BlendMode.srcATop,
                            ),
                            child: child,
                          ),
                          child: render3d
                              ? MossAvatar(
                                  key: ValueKey(
                                    'avatar-${profile.characterId}',
                                  ),
                                  mood: mood,
                                  emotion: emotion.emotion,
                                  look: profile.look,
                                  sky: sky,
                                  gaze: gaze,
                                  atmosphere: atmosphere,
                                )
                              : Center(
                                  child: Icon(
                                    switch (profile.look.accessory) {
                                      CharacterAccessory.leafCrown =>
                                        Icons.eco_rounded,
                                      CharacterAccessory.sunHat =>
                                        Icons.wb_sunny_rounded,
                                      CharacterAccessory.rainCloud =>
                                        Icons.water_drop_rounded,
                                    },
                                    size: 88,
                                    color: profile.look.accentColor,
                                  ),
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Suasana sebelumnya',
                              onPressed: () => _stepSky(next: false),
                              icon: Icon(
                                Icons.chevron_left_rounded,
                                color: skyInk,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Geser untuk mengubah suasana',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: skyInk, fontSize: 11),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Suasana berikutnya',
                              onPressed: () => _stepSky(next: true),
                              icon: Icon(
                                Icons.chevron_right_rounded,
                                color: skyInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                        child: Column(
                          children: [
                            Text(
                              state.moodMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.6,
                                color: skyInk,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              state.explanation,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: skyInk,
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextButton.icon(
                              onPressed: onPickCharacter,
                              icon: Icon(
                                Icons.auto_awesome_rounded,
                                size: 15,
                                color: skyInk,
                              ),
                              label: Text(
                                '${profile.charName} · ganti karakter',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: skyInk,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                PredictionCard(reading: emotion, look: profile.look),
                const SizedBox(height: 25),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Kondisi tanaman',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    Text(
                      state.isLive
                          ? 'DATA SENSOR'
                          : state.isSerialSnapshot
                          ? 'DATA SERIAL'
                          : 'BELUM TERHUBUNG',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: mutedColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (state.isLive || state.isSerialSnapshot) ...[
                  Text(
                    'Nilai sensor belum diverifikasi; tanah dan cahaya berupa skala relatif.',
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columnWidth = (constraints.maxWidth - 10) / 2;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: columnWidth,
                          child: _Metric(
                            icon: Icons.water_drop_outlined,
                            title: 'Kelembapan tanah',
                            value: state.soilPercent != null
                                ? _percent(state.soilPercent)
                                : 'Belum terbaca',
                            detail: state.soilPercent != null
                                ? state.soilAdc != null
                                      ? 'ADC ${state.soilAdc}'
                                      : 'Belum tersedia'
                                : state.soilAdc != null
                                ? state.soilAdc == 0
                                      ? 'ADC 0 · sinyal tidak valid; pompa dikunci'
                                      : 'ADC ${state.soilAdc} · penyebab belum diketahui'
                                : 'Menunggu sensor',
                            color: const Color(0xFF51859A),
                          ),
                        ),
                        SizedBox(
                          width: columnWidth,
                          child: _Metric(
                            icon: Icons.waves_rounded,
                            title: 'Level air',
                            value: switch (state.waterLevel) {
                              WaterLevel.empty => 'Empty',
                              WaterLevel.low => 'Low',
                              WaterLevel.medium => 'Medium',
                              WaterLevel.full => 'Full',
                              null => 'Belum terbaca',
                            },
                            detail: state.waterAdc != null
                                ? state.waterEmpty == true
                                      ? 'ADC ${state.waterAdc} · empty'
                                      : 'ADC ${state.waterAdc}'
                                : 'Belum tersedia',
                            color: const Color(0xFF568896),
                          ),
                        ),
                        SizedBox(
                          width: columnWidth,
                          child: _Metric(
                            icon: Icons.thermostat_rounded,
                            title: 'Suhu udara',
                            value: state.temperatureC == null
                                ? '—'
                                : '${state.temperatureC!.toStringAsFixed(1)}°',
                            detail: state.humidityPercent == null
                                ? 'Menunggu sensor'
                                : 'Kelembapan ${state.humidityPercent}%',
                            color: terracotta,
                          ),
                        ),
                        SizedBox(
                          width: columnWidth,
                          child: _Metric(
                            icon: Icons.wb_sunny_outlined,
                            title: 'Cahaya',
                            value: state.lightPercent != null
                                ? _percent(state.lightPercent)
                                : '—',
                            detail: state.lightAdc != null
                                ? state.lightPercent != null
                                      ? 'ADC ${state.lightAdc}'
                                      : 'ADC ${state.lightAdc} · belum dapat diestimasi'
                                : state.lightPercent != null
                                ? 'Belum tersedia'
                                : 'Menunggu sensor',
                            color: const Color(0xFFAB843A),
                          ),
                        ),
                        SizedBox(
                          width: constraints.maxWidth,
                          child: _Metric(
                            icon: Icons.wb_twilight_rounded,
                            title: 'UV',
                            value:
                                (state.uvAdcPercent == null
                                    ? null
                                    : '~${state.uvAdcPercent}%') ??
                                state.uvIndex?.toStringAsFixed(1) ??
                                '—',
                            detail: state.uvAdc != null
                                ? 'ADC ${state.uvAdc}'
                                : state.uvIndex == null
                                ? 'Menunggu data sensor'
                                : 'Belum diverifikasi',
                            color: const Color(0xFF967144),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                _AirRow(state: state),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.live,
    required this.snapshot,
    required this.connecting,
  });
  final bool live;
  final bool snapshot;
  final bool connecting;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: live ? const Color(0xFFDDE9DA) : const Color(0xFFE9EAE4),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          live ? Icons.sensors_rounded : Icons.cloud_off_outlined,
          size: 14,
          color: live ? forest : muted,
        ),
        const SizedBox(width: 5),
        Text(
          live
              ? 'SENSOR'
              : (snapshot ? 'SERIAL' : (connecting ? 'MENYAMBUNG' : 'OFFLINE')),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w800,
            color: live ? forest : muted,
          ),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.live, required this.sourceNotice});
  final bool live;
  final String sourceNotice;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
    decoration: BoxDecoration(
      color: context.mossColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: context.mossColors.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(
          live ? Icons.sensors_rounded : Icons.wifi_off_rounded,
          size: 19,
          color: context.mossColors.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            sourceNotice,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.color,
  });
  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: context.mossColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: context.mossColors.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 12),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.mossColors.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.7,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          detail,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.mossColors.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

class _AirRow extends StatelessWidget {
  const _AirRow({required this.state});
  final PlantState state;

  @override
  Widget build(BuildContext context) {
    final raw = state.mqAdc;
    final rail = raw == 0 || raw == 4095;
    final gas = state.mqGasIndex;
    final gasStatus = switch (state.mqGasStatus) {
      'baseline' => 'Sinyal di baseline sesi',
      'slight' => 'Sedikit di atas baseline',
      'elevated' => 'Perubahan gas jelas',
      'high' => 'Perubahan gas tinggi',
      _ => 'Indeks belum tersedia',
    };
    final detail = state.mqAdcStatus == 'adc_read_failed'
        ? state.mqAdcUnit == 'ADC1'
              ? 'Analog gagal dibaca pada ADC1.'
              : 'Analog gagal dibaca; ADC2 bisa berbenturan dengan Wi-Fi.'
        : gas != null
        ? '$gasStatus · relatif'
        : rail
        ? 'ADC mencapai batas; penyebab belum diketahui.'
        : raw != null
        ? 'Indeks gas belum tersedia.'
        : state.mqDigital != null
        ? 'Analog belum tersedia.'
        : 'Belum tersedia dan belum dikalibrasi';
    final detailStyle = TextStyle(
      fontSize: 11,
      height: 1.4,
      color: context.mossColors.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.mossColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: context.mossColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.air_rounded, color: context.mossColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sensor udara MQ135',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(detail, style: detailStyle),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    gas?.toString() ?? '—',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: context.mossColors.primary,
                    ),
                  ),
                  Text(
                    gas == null ? 'belum tersedia' : 'indeks gas 0–100',
                    style: detailStyle,
                  ),
                ],
              ),
            ],
          ),
          if (raw != null) ...[
            const SizedBox(height: 10),
            Text(
              'ADC $raw · ${state.isSerialSnapshot ? 'snapshot' : 'terbaru'}',
              style: detailStyle,
            ),
          ],
          if (state.mqAverageAdc != null && state.mqAverageSamples > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Rata-rata ${state.mqAverageSamples}/12 sampel: ${state.mqAverageAdc} ADC',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            if (state.mqTrend != null) ...[
              const SizedBox(height: 2),
              Text(switch (state.mqTrend) {
                1 => 'Arah sinyal: naik terhadap awal jendela.',
                -1 => 'Arah sinyal: turun terhadap awal jendela.',
                _ => 'Arah sinyal: stabil dalam batas derau.',
              }, style: detailStyle),
            ],
          ] else if (state.isLocalLive) ...[
            const SizedBox(height: 12),
            Text(
              'Rata-rata menunggu sinyal analog non-rel.',
              style: detailStyle,
            ),
          ],
          if (state.mqPinMillivolts != null) ...[
            const SizedBox(height: 4),
            Text(
              'Tegangan pin: ~${state.mqPinMillivolts} mV',
              style: detailStyle,
            ),
          ],
          if (state.mqGasBaselineMv != null) ...[
            const SizedBox(height: 2),
            Text(
              'Baseline sesi: ~${state.mqGasBaselineMv} mV',
              style: detailStyle,
            ),
          ],
          if (state.mqDigital != null) ...[
            const SizedBox(height: 4),
            Text(
              'D0 = ${state.mqDigital}: level komparator, bukan ppm.',
              style: detailStyle,
            ),
          ],
          const SizedBox(height: 10),
          Text('MQ135 · gas umum (asap/VOC)', style: detailStyle),
        ],
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.cloudSettings,
    required this.serialMessage,
    required this.hasSerialSnapshot,
    required this.onImportSerial,
    required this.onClearSerial,
    required this.localSelected,
    required this.localStatus,
    required this.localMessage,
    required this.onConnectLocal,
    required this.onDisconnectLocal,
    required this.appearance,
    required this.storageUnavailable,
    required this.onThemeChanged,
    required this.onSkyChanged,
    required this.onManualTimeChanged,
    required this.profiles,
    required this.onSelectProfile,
    required this.onSaveProfile,
    required this.onDeleteProfile,
    required this.render3d,
    required this.onTestNotification,
    required this.onRequestNotificationPermission,
  });
  final Widget? cloudSettings;
  final String? serialMessage;
  final bool hasSerialSnapshot;
  final VoidCallback onImportSerial;
  final VoidCallback onClearSerial;
  final bool localSelected;
  final LocalWifiStatus localStatus;
  final String localMessage;
  final VoidCallback onConnectLocal;
  final VoidCallback onDisconnectLocal;
  final AppearanceSettings appearance;
  final bool storageUnavailable;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<SkyChoice> onSkyChanged;
  final ValueChanged<int> onManualTimeChanged;
  final ProfileSettings profiles;
  final Future<void> Function(String) onSelectProfile;
  final Future<void> Function(DeviceProfile) onSaveProfile;
  final Future<void> Function(String) onDeleteProfile;
  final bool render3d;
  final VoidCallback onTestNotification;
  final VoidCallback onRequestNotificationPermission;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'PREFERENSI',
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w800,
          color: context.mossColors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 7),
      const Text(
        'Pengaturan',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
      ),
      const SizedBox(height: 24),
      AppearancePanel(
        settings: appearance,
        storageUnavailable: storageUnavailable,
        onThemeChanged: onThemeChanged,
        onSkyChanged: onSkyChanged,
        onManualTimeChanged: onManualTimeChanged,
      ),
      const Divider(height: 32),
      ?cloudSettings,
      ProfilePanel(
        settings: profiles,
        localSelected: localSelected,
        localStatus: localStatus,
        localMessage: localMessage,
        onConnect: onConnectLocal,
        onDisconnect: onDisconnectLocal,
        onSave: onSaveProfile,
        onSelect: onSelectProfile,
        onDelete: onDeleteProfile,
        render3d: render3d,
      ),
      const Divider(height: 32),
      const Text(
        'Wi-Fi lokal ESP32',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 5),
      const Text(
        'Pilih Wi-Fi Moss pada ponsel menggunakan sandi di LCD ESP32, '
        'lalu hubungkan di sini. Data tetap di jaringan lokal; jaringan ini '
        'tidak menyediakan internet.',
        style: TextStyle(fontSize: 12, height: 1.4),
      ),
      Text(localMessage, style: const TextStyle(fontSize: 12)),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: localStatus == LocalWifiStatus.connecting
                ? null
                : onConnectLocal,
            child: const Text('Hubungkan Wi-Fi lokal'),
          ),
          if (localSelected)
            TextButton(
              onPressed: onDisconnectLocal,
              child: const Text('Putuskan Wi-Fi lokal'),
            ),
        ],
      ),
      const Divider(height: 32),
      const Text('Data serial', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      const Text(
        'Salin satu baris JSON sample dari ESP32, lalu tempel di sini. '
        'Snapshot bukan live. Data tempel hanya di memori; data bawaan APK dapat muncul kembali saat dibuka.',
        style: TextStyle(fontSize: 12, height: 1.4),
      ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: onImportSerial,
            child: const Text('Tempel data serial'),
          ),
          if (hasSerialSnapshot)
            TextButton(
              onPressed: onClearSerial,
              child: const Text('Hapus snapshot'),
            ),
        ],
      ),
      if (serialMessage != null)
        Text(serialMessage!, style: const TextStyle(fontSize: 12)),
      const Divider(height: 32),
      const Text(
        'Notifikasi HP',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 5),
      Text(
        'Peringatan air rendah dan prediksi berkala muncul di notifikasi '
        'Android. Data real-time hanya masuk saat aplikasi terhubung ke '
        'perangkat; notifikasi berkala memakai prediksi terakhir.',
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: context.mossColors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: onRequestNotificationPermission,
            icon: const Icon(Icons.notifications_outlined, size: 18),
            label: const Text('Izinkan notifikasi'),
          ),
          TextButton.icon(
            onPressed: onTestNotification,
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('Tes notifikasi'),
          ),
        ],
      ),
      const Divider(height: 32),
      const AppVersionPanel(),
    ],
  );
}
