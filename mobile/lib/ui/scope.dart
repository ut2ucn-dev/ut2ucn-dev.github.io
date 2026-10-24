import 'package:flutter/widgets.dart';

import '../data/store.dart';
import '../services/settings.dart';

/// Makes the [AppStore] available to every screen; widgets that read it
/// with [StoreScope.of] rebuild whenever it changes.
class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  /// For callbacks: the store without subscribing to its changes.
  static AppStore read(BuildContext context) => context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

class SettingsScope extends InheritedNotifier<Settings> {
  const SettingsScope({super.key, required Settings settings, required super.child}) : super(notifier: settings);

  static Settings of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;

  static Settings read(BuildContext context) => context.getInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}

extension ScopeX on BuildContext {
  AppStore get store => StoreScope.of(this);
  AppStore get storeRead => StoreScope.read(this);
}
