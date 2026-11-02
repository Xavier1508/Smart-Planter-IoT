import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_planter/src/app_mode.dart';
import 'package:smart_planter/src/cloud_controller.dart';
import 'package:smart_planter/src/moss_app.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('online mode starts at a clear sign-in screen', (tester) async {
    late final SupabaseClient client;
    await tester.runAsync(() async {
      client = SupabaseClient(
        'http://127.0.0.1:1',
        'sb_publishable_fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
    });
    final cloud = CloudController(client);
    await tester.pumpWidget(
      MossApp(
        render3d: false,
        cloud: cloud,
        initialMode: AppMode.online,
        autoConnectLocal: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selamat datang di Tunas'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Masuk'), findsOneWidget);
    expect(find.text('Buat akun'), findsOneWidget);
    expect(find.text('Gunakan mode offline'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pump();
    expect(find.text('Masukkan email yang valid.'), findsOneWidget);
    expect(find.text('Minimal 6 karakter.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    cloud.dispose();
    await tester.runAsync(client.dispose);
  });

  testWidgets('offline mode opens the dashboard and can switch back online', (
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
    await tester.pumpWidget(
      MossApp(
        render3d: false,
        cloud: cloud,
        initialMode: AppMode.offline,
        autoConnectLocal: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hari ini'), findsOneWidget);
    await tester.tap(find.text('Pengaturan'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Mode offline'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Mode offline'), findsOneWidget);
    await tester.tap(find.text('Masuk ke mode online'));
    await tester.pumpAndSettle();
    expect(find.text('Selamat datang di Tunas'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    cloud.dispose();
    await tester.runAsync(client.dispose);
  });
}
