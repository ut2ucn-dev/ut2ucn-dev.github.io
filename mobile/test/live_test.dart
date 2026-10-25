import 'package:flutter_test/flutter_test.dart';
import 'package:stemik/data/store.dart';
import 'package:stemik/demo/demo_api.dart';

import 'store_test.dart' show MemoryFiles, openStore;

void main() {
  test("someone else's change shows up without a refresh", () async {
    final api = DemoApi();
    final store = await openStore(api, MemoryFiles());
    await Future<void>.delayed(Duration.zero);
    expect(store.live, isTrue);

    var reloaded = 0;
    store.remoteChanges.listen((_) => reloaded++);
    // Another admin renames a student on the web.
    final s = api.students.first;
    s['name'] = 'Нове Імʼя';
    api.simulateRemoteChange();
    api.simulateRemoteChange(); // a burst is one reload
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(reloaded, 1);
    expect(store.data.studentById[s['id']]!.name, 'Нове Імʼя');
    await store.close(discardPending: false);
    expect(store.live, isFalse);
  });

  test('teachers and extra windows do not listen', () async {
    final teacher = await openStore(DemoApi(role: 'teacher'), MemoryFiles());
    await Future<void>.delayed(Duration.zero);
    expect(teacher.live, isFalse);
    await teacher.close(discardPending: false);

    final api = DemoApi();
    final window = AppStore(api, MemoryFiles(), watchLive: false);
    final me = await openStore(api, MemoryFiles());
    await window.open(me.me);
    await Future<void>.delayed(Duration.zero);
    expect(window.live, isFalse);
    await window.close(discardPending: false);
    await me.close(discardPending: false);
  });
}
