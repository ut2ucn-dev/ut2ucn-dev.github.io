import '../data/parent_portal.dart';
import '../util/dates.dart';

/// Made-up parents' portal for the demo build and tests: two children, one
/// with a bit of everything (subscription, certificate, trial, an unpaid
/// lesson, printed and waiting models). Any phone and password sign in.
class DemoParentApi implements ParentApi {
  @override
  Future<ParentSession> login(String phone, String password) async {
    if (password.trim().isEmpty) throw ParentLoginFailed('Невірний телефон або пароль');
    return const ParentSession(token: 'demo-parent-token', name: 'Коваль Ірина', phone: '380671234567');
  }

  @override
  Future<void> logout(String token) async {}

  @override
  Future<ParentPortal> fetchPortal(String token) async {
    if (token != 'demo-parent-token') throw ParentSessionExpired();
    final today = todayStr();
    String day(int n) => addDays(today, n);
    Map<String, dynamic> lesson(
      String id,
      int offset,
      String course,
      String theme, {
      String format = 'group',
      String? status,
      String? pay,
      double? amount,
      double? due,
      bool trial = false,
      bool print = false,
    }) => {
      'id': id,
      'date': day(offset),
      'time': '15:30:00',
      'duration_minutes': 60,
      'course': course,
      'format': format,
      'theme': theme,
      'room': 'Клас 3D',
      'teacher': 'Олена Іваненко',
      'status': status,
      'payment_method': pay,
      'amount': amount,
      'due': due,
      'print_enabled': print,
      'trial': trial,
    };
    Map<String, dynamic> work(
      String lessonId,
      int offset,
      String course,
      String theme,
      bool printed, {
      bool trial = false,
    }) => {
      'lesson_id': lessonId,
      'date': day(offset),
      'course': course,
      'format': 'group',
      'theme': theme,
      'photo': null,
      'printed': printed,
      'trial': trial,
      'print_enabled': false,
    };
    const makers = '3D Makers FIRST (6-8)';
    const robo = 'Robo AI (Ukit 6-8)';
    return ParentPortal({
      'parent': {'name': 'Коваль Ірина', 'phone': '380671234567'},
      'today': today,
      'payments_enabled': false,
      'students': [
        {
          'id': 'demo-kid-1',
          'name': 'Марко Коваль',
          'photo': null,
          'lessons': [
            lesson('l7', 5, robo, 'Робот-помічник'),
            lesson('l6', 2, makers, 'Космічна станція'),
            lesson('l5', -5, makers, 'Робот', format: 'group_online', status: 'present', due: 470, print: true),
            lesson('l4', -12, makers, 'Динозавр', status: 'excused'),
            lesson('l3', -19, makers, 'Космічна ракета', status: 'present', pay: 'subscription', amount: 350),
            lesson('l2', -26, makers, 'Брелок з іменем', status: 'present', pay: 'subscription', amount: 350),
            lesson('l1', -33, makers, 'Перша модель', status: 'present', pay: 'certificate', amount: 400, trial: true),
          ],
          'works': [
            work('l5', -5, makers, 'Робот', false),
            work('l3', -19, makers, 'Космічна ракета', false),
            work('l2', -26, makers, 'Брелок з іменем', true),
            work('l1', -33, makers, 'Перша модель', true, trial: true),
          ],
          'subscriptions': [
            {
              'id': 'sub1',
              'course': makers,
              'total_lessons': 4,
              'remaining_lessons': 2,
              'total_price': 1400,
              'status': 'active',
              'purchased_at': '${day(-26)}T00:00:00+00:00',
              'payment_method': 'card',
            },
          ],
        },
        {
          'id': 'demo-kid-2',
          'name': 'Софія Коваль',
          'photo': null,
          'lessons': [
            lesson('s2', 3, 'VR ІГРОВИЙ', 'Віртуальна галерея'),
            lesson('s1', -4, 'VR ІГРОВИЙ', 'Знайомство з VR', status: 'present', pay: 'card', amount: 450, trial: true),
          ],
          'works': [],
          'subscriptions': [],
        },
      ],
    });
  }
}
