import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/api.dart';
import 'data/local_files.dart';
import 'data/parent_portal.dart';
import 'data/store.dart';
import 'data/supabase_api.dart';
import 'data/supabase_parent_api.dart';
import 'demo/demo_api.dart';
import 'demo/demo_parent_api.dart';
import 'desktop/platform.dart';
import 'desktop/windows.dart';
import 'services/reminders.dart';
import 'services/settings.dart';
import 'ui/app.dart';

/// `--dart-define=STEMIK_DEMO=true` runs on made-up data with no backend
/// (for previews and screenshots).
const demoMode = bool.fromEnvironment('STEMIK_DEMO');

/// An extra Mac window is started with the arguments ["window", <spec>]
/// (desktop/windows.dart).
Future<void> main(List<String> args) async {
  if (args.length >= 2 && args.first == 'window') return runWindow(args[1]);
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('uk');
  final settings = await Settings.load();
  final StemikApi api;
  final ParentApi parentApi;
  if (demoMode) {
    api = DemoApi();
    parentApi = DemoParentApi();
  } else {
    await SupabaseApi.initialize();
    api = SupabaseApi();
    parentApi = SupabaseParentApi();
  }
  final files = LocalFiles.create();
  final store = AppStore(api, files);
  if (hasNativeMenuBar && !demoMode) AppWindows.start(store, files, settings);
  final reminders = Reminders(store, settings);
  try {
    await reminders.init();
  } catch (e, st) {
    // Reminders are a convenience; the app must still open without them.
    debugPrint('Reminders unavailable: $e\n$st');
  }
  runApp(StemikApp(store: store, parentApi: parentApi, settings: settings, reminders: reminders));
}
