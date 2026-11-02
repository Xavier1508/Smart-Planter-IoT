import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_planter/src/app_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mode choice persists and invalid values are ignored', () async {
    SharedPreferences.setMockInitialValues({});
    const store = AppModeStore();
    expect(await store.read(), isNull);

    await store.write(AppMode.offline);
    expect(await store.read(), AppMode.offline);

    await store.write(AppMode.online);
    expect(await store.read(), AppMode.online);
  });
}
