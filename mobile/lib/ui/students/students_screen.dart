import 'package:flutter/material.dart';

import '../contact.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'bulk_add_screen.dart';
import 'student_card_screen.dart';
import 'student_edit_screen.dart';

/// The studio's one shared roster.
class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final all = store.data.students;
    final q = _query.text.trim().toLowerCase();
    final list = q.isEmpty
        ? all
        : all
              .where(
                (s) => [
                  s.name,
                  s.phone,
                  s.parentLastName,
                  s.parentFirstName,
                ].whereType<String>().join(' ').toLowerCase().contains(q),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Учні студії'),
        actions: [
          IconButton(
            tooltip: 'Додати кількох',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BulkAddScreen())),
            icon: const Icon(Icons.group_add_rounded),
          ),
          const SyncButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StudentEditScreen())),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Учень', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: "Пошук за ім'ям, телефоном, батьками…",
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(onPressed: () => setState(_query.clear), icon: const Icon(Icons.close_rounded)),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: store.refresh,
              child: list.isEmpty
                  ? ListView(
                      children: [
                        all.isEmpty
                            ? const EmptyState(
                                emoji: '🧒',
                                title: 'Учнів ще немає',
                                subtitle: 'Додайте першого учня кнопкою внизу.',
                              )
                            : const EmptyState(
                                emoji: '🔍',
                                title: 'Нічого не знайдено',
                                subtitle: 'Спробуйте інший запит.',
                              ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: list.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                            child: Text(
                              '${list.length} з ${all.length}',
                              style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w600, fontSize: 12.5),
                            ),
                          );
                        }
                        final s = list[i - 1];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () =>
                                  Navigator.of(context)
                                      .push(MaterialPageRoute(builder: (_) => StudentCardScreen(studentId: s.id))),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                                child: Row(
                                  children: [
                                    Avatar(initial: s.initial, url: store.isAdmin ? s.photo : null, size: 42),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s.name,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                                          ),
                                          if (s.parentsName.isNotEmpty || s.phone != null)
                                            Text(
                                              [s.parentsName, ?s.phone].where((e) => e.isNotEmpty).join(' · '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: c.inkSoft, fontSize: 13),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (s.phone != null)
                                      ContactButtons(phone: s.phone!, compact: true, only: const ['call']),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
