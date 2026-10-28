import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/cloud_controller.dart';
import 'package:smart_planter/src/moss_app.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('cloud account form validates empty input without a request', (
    tester,
  ) async {
    late final SupabaseClient client;
    await tester.runAsync(() async {
      client = SupabaseClient(
        'http://127.0.0.1:1',
        'sb_publishable_fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
    });
    final cloud = CloudController(client);
    await tester.pumpWidget(MossApp(render3d: false, cloud: cloud));
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();

    expect(find.text('Masuk untuk melihat perangkat Anda.'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Kata sandi'), findsOneWidget);
    await tester.ensureVisible(find.text('Masuk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Masuk'));
    await tester.pump();
    expect(
      find.text('Isi email dan kata sandi terlebih dahulu.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    cloud.dispose();
    await tester.runAsync(client.dispose);
  });
}
