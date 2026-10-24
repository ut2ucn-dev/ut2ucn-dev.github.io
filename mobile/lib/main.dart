import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/api.dart';
import 'data/local_files.dart';
import 'data/store.dart';
import 'data/supabase_api.dart';
import 'demo/demo_api.dart';
import 'services/reminders.dart';
import 'services/settings.dart';
import 'ui/app.dart';

/// `--dart-define=STEMIK_DEMO=true` runs on made-up data with no backend
/// (for previews and screenshots).
const demoMode = bool.fromEnvironment('STEMIK_DEMO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('uk');
  final settings = await Settings.load();
  final StemikApi api;
  if (demoMode) {
    api = DemoApi();
  } else {
    await SupabaseApi.initialize();
    api = SupabaseApi();
  }
  final store = AppStore(api, LocalFiles.create());
  final reminders = Reminders(store, settings);
  await reminders.init();
  runApp(StemikApp(store: store, settings: settings, reminders: reminders));
}
