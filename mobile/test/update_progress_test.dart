import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/update_progress.dart';

void main() {
  test('percentages use only valid SDK byte counts', () {
    expect(UpdateProgress.fromEvent(null), isNull);
    expect(UpdateProgress.fromEvent({'status': 7}), isNull);
    final unknown = UpdateProgress.fromEvent({
      'status': 'DOWNLOADING',
      'downloaded': -1,
      'total': 0,
    })!;
    expect(unknown.fraction, isNull);
    expect(unknown.isVisible, isTrue);
    final partial = UpdateProgress.fromEvent({
      'status': 'DOWNLOADING',
      'downloaded': 25,
      'total': 100,
    })!;
    expect(partial.fraction, .25);
    final over = UpdateProgress.fromEvent({
      'status': 'DOWNLOADING',
      'downloaded': 150,
      'total': 100,
    })!;
    expect(over.fraction, isNull);
    expect(UpdateProgress.fromEvent({'status': 'UNKNOWN'})!.isVisible, isFalse);
  });

  testWidgets('shows real progress and distinguishes download from install', (
    tester,
  ) async {
    final events = StreamController<Object?>.broadcast();
    addTearDown(events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateProgressHost(
          events: events.stream,
          child: const Scaffold(body: Text('Moss')),
        ),
      ),
    );
    events.add({'status': 'CHECKING'});
    await tester.pump();
    await tester.pump();
    expect(find.text('Memeriksa pembaruan Moss…'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );

    events.add({'status': 'DOWNLOADING', 'downloaded': 25, 'total': 100});
    await tester.pump();
    await tester.pump();
    expect(find.text('Mengunduh pembaruan Moss…'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .25,
    );

    events.add({'status': 'DOWNLOADING', 'downloaded': -1, 'total': -1});
    await tester.pump();
    await tester.pump();
    expect(find.text('25%'), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );

    events.add({'status': 'DOWNLOADED', 'downloaded': 100, 'total': 100});
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Unduhan selesai. Lanjutkan pemasangan di Android.'),
      findsOneWidget,
    );
    expect(find.textContaining('berhasil dipasang'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.byTooltip('Tutup informasi pembaruan'));
    await tester.pump();
    expect(
      find.text('Unduhan selesai. Lanjutkan pemasangan di Android.'),
      findsNothing,
    );

    events.add({'status': 'INSTALL_CANCELED'});
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Pemasangan dibatalkan; Moss yang lama tetap ada.'),
      findsOneWidget,
    );
    events.add({'status': 'UPDATE_FAILED'});
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Pembaruan tidak selesai. Coba lagi nanti.'),
      findsOneWidget,
    );
    events.add({'status': 'NEW_RELEASE_NOT_AVAILABLE'});
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Pembaruan tidak selesai. Coba lagi nanti.'),
      findsNothing,
    );
    expect(find.text('Moss'), findsOneWidget);
  });

  testWidgets('channel errors do not leave a stale progress indicator', (
    tester,
  ) async {
    final events = StreamController<Object?>.broadcast();
    addTearDown(events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateProgressHost(
          events: events.stream,
          child: const Scaffold(body: Text('Moss')),
        ),
      ),
    );
    events.add({'status': 'DOWNLOADING', 'downloaded': 1, 'total': 2});
    await tester.pump();
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);
    events.addError(StateError('channel unavailable'));
    await tester.pump();
    await tester.pump();
    expect(find.text('50%'), findsNothing);
    expect(find.text('Moss'), findsOneWidget);
  });
}
