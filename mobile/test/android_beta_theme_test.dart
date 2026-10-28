import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('beta manifest declares an AppCompat application theme', () {
    final overlay = File('android/app/src/beta/AndroidManifest.xml')
        .readAsStringSync();
    final styles = File('android/app/src/beta/res/values/styles.xml')
        .readAsStringSync();
    final mainManifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(overlay, contains('android:theme="@style/MossBetaAppTheme"'));
    expect(overlay, contains('android.permission.INTERNET'));
    expect(styles, contains('parent="Theme.AppCompat.DayNight.NoActionBar"'));
    expect(
      gradle,
      contains(
        'add("betaImplementation", "androidx.appcompat:appcompat:1.7.1")',
      ),
    );
    expect(mainManifest, contains('android:theme="@style/LaunchTheme"'));
    expect(mainManifest, isNot(contains('MossBetaAppTheme')));
  });
}
