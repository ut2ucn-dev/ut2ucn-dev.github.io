import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/photos.dart';
import '../util/dates.dart';
import '../util/domain.dart';
import 'schedule/lesson_screen.dart';
import 'scope.dart';
import 'split.dart';
import 'theme.dart';
import 'widgets.dart';

/// Works waiting for the 3D printer: one row per child marked "П" on a 3D
/// lesson that has already happened.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final c = context.c;
    final data = store.data;
    final rows = data.queue(store.ownedLessons, includePrinted: _all);
    return Scaffold(
      appBar: AppBar(
        title: Text(store.isAdmin && store.teacherFilter == null ? 'Черга друку студії' : 'Черга друку'),
        actions: const [SyncButton()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Очікують')),
                  ButtonSegment(value: true, label: Text('Усі')),
                ],
                selected: {_all},
                onSelectionChanged: (s) => setState(() => _all = s.first),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: store.refresh,
              child: rows.isEmpty
                  ? ListView(
                      children: [
                        EmptyState(
                          emoji: '🖨️',
                          title: _all ? 'Записів немає' : 'Черга порожня',
                          subtitle: "Роботи з'являться тут після відмітки «П» на 3D-занятті.",
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final printed = r.work?.printed ?? false;
                        final owner = data.profileById[r.lesson.ownerId];
                        final accent = c.course(r.lesson.course);
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => openPage(context, LessonScreen(lessonId: r.lesson.id)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  WorkPhoto(
                                    work: r.work,
                                    size: 64,
                                    onCamera: () async {
                                      final bytes = await pickPhoto(context, title: 'Фото роботи · ${r.student.name}');
                                      if (bytes != null) await store.attachWorkPhoto(r.lesson, r.student, bytes);
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (r.lesson.course != null)
                                          Text(
                                            r.lesson.course!,
                                            style: TextStyle(
                                              color: accent.color,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        Text(
                                          r.student.name,
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                                        ),
                                        Text(
                                          '${r.lesson.theme} · ${lessonCardDateTitle(r.lesson.date)}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: c.inkSoft, fontSize: 12.5),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            PrintedPill(
                                              printed: printed,
                                              onTap: () {
                                                HapticFeedback.selectionClick();
                                                store.setPrinted(r.lesson, r.student, !printed);
                                              },
                                            ),
                                            if (isOnlineFormat(r.lesson.format))
                                              Tag(lessonFormatLabel(r.lesson, r.attendance)),
                                            if (store.isAdmin && owner != null)
                                              Tag(owner.fullName, icon: Icons.person_rounded),
                                          ],
                                        ),
                                        if (printed && r.work?.printedByName != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              'Статус змінив: ${r.work!.printedByName}',
                                              style: TextStyle(color: c.inkSoft, fontSize: 12),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
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
