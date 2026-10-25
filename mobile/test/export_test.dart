import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stemik/data/models.dart';
import 'package:stemik/demo/demo_api.dart';
import 'package:stemik/desktop/desktop_shell.dart';
import 'package:stemik/export/export_doc.dart';
import 'package:stemik/export/pdf_writer.dart';
import 'package:stemik/export/reports.dart';
import 'package:stemik/export/xlsx_writer.dart';
import 'package:stemik/ui/payroll_screen.dart';
import 'package:stemik/util/dates.dart';

import 'desktop_test.dart' show closeMacApp, mac, pumpMacApp;
import 'store_test.dart' show MemoryFiles, openStore;

/// `STEMIK_EXPORT_DIR=/some/dir flutter test test/export_test.dart` also
/// writes the files there, to open them in Excel or a PDF viewer.
void keep(String name, List<int> bytes) {
  final dir = Platform.environment['STEMIK_EXPORT_DIR'];
  if (dir != null) File('$dir/$name').writeAsBytesSync(bytes);
}

const sample = ExportDoc(
  title: 'Зарплата студії',
  period: '01.10.2026 – 25.10.2026',
  fileStem: 'Stemik — Зарплата студії 01.10.2026–25.10.2026',
  summary: [('ЗП по студії', '1 200 грн')],
  tables: [
    ExportTable(
      title: 'Заняття',
      columns: [
        ExportColumn('Дата', kind: ColKind.date),
        ExportColumn('Тема'),
        ExportColumn('Учнів', kind: ColKind.integer),
        ExportColumn('ЗП', kind: ColKind.money),
      ],
      rows: [
        ['2026-10-01', 'Брелок <з> "іменем" & сердечком', 3, 400],
        ['2026-10-02', 'Робот', 1, 800.5],
      ],
      total: ['Разом', null, 4, 1200.5],
    ),
    ExportTable(title: 'Порожня', columns: [ExportColumn('Щось')], rows: [], empty: 'Немає.'),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('xlsx: a sheet per table, real numbers and dates, escaped text', () {
    final bytes = buildXlsx(sample);
    keep(sample.fileName(ExportFormat.xlsx), bytes);
    final zip = ZipDecoder().decodeBytes(bytes);
    String file(String name) => utf8.decode(zip.findFile(name)!.content as List<int>);

    expect(file('xl/workbook.xml'), allOf(contains('name="Заняття"'), contains('name="Порожня"')));
    final sheet = file('xl/worksheets/sheet1.xml');
    expect(sheet, contains('Зарплата студії — Заняття'));
    expect(sheet, contains('Брелок &lt;з&gt; &quot;іменем&quot; &amp; сердечком'));
    expect(sheet, contains('<v>800.5</v>'));
    // 1 Oct 2026 is day 46296 counting from Excel's 30 Dec 1899.
    expect(sheet, contains('<v>46296</v>'));
    expect(sheet, contains('state="frozen"'));
    expect(file('xl/worksheets/sheet2.xml'), contains('Немає.'));
    expect(file('[Content_Types].xml'), contains('/xl/worksheets/sheet2.xml'));
  });

  test('pdf: a real PDF with the app font', () async {
    final bytes = await buildPdf(sample, await PdfAssets.load());
    keep(sample.fileName(ExportFormat.pdf), bytes);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(5000));
  });

  test('file names drop characters a file system refuses', () {
    const doc = ExportDoc(title: 't', period: 'p', fileStem: 'Звіт: 01/10', tables: []);
    expect(doc.fileName(ExportFormat.pdf), 'Звіт- 01-10.pdf');
  });

  test('payroll, studio report and print costs match the data', () async {
    final api = DemoApi();
    final store = await openStore(api, MemoryFiles());
    final from = isoDate(DateTime.now().subtract(const Duration(days: 30)));
    final to = todayStr();

    final payroll = payrollDoc(store, from, to);
    final inRange = store.ownedLessons.where((l) => l.date.compareTo(from) >= 0 && l.date.compareTo(to) <= 0);
    final pay = inRange.fold<double>(0, (s, l) => s + l.payrollAmount);
    expect(payroll.tables.map((t) => t.title), ['Викладачі', 'Заняття']);
    expect(payroll.tables.first.total![2], pay);
    expect(payroll.tables.last.rows, hasLength(inRange.length));

    final report = studioReportDoc(
      from: from,
      to: to,
      summary: (await api.fetchReportSummary(from, to))!,
      paid: await api.fetchReportView('report_paid', from: from, to: to, orderBy: 'lesson_date'),
      debt: await api.fetchReportView('report_debt', from: from, to: to, orderBy: 'lesson_date'),
      subscriptions: await api.fetchReportView('report_unused_subscriptions', orderBy: 'purchased_at'),
      excused: const [],
    );
    expect(report.tables.map((t) => t.title), ['Оплачено', 'Заборгованість', 'Невикористані']);

    final rows = (await api.fetchPrintCosts(from, to)).map(PrintCost.new).toList();
    final costs = printCostsDoc(rows, from, to);
    final total = rows.fold<double>(0, (s, r) => s + (r.totalCost ?? 0));
    expect(costs.tables.first.total!.last, closeTo(total, 0.001));
    expect(costs.tables.last.rows, hasLength(rows.where((r) => r.totalCost == null).length));
    for (final f in ExportFormat.values) {
      keep(
        costs.fileName(f),
        f == ExportFormat.xlsx ? buildXlsx(costs) : await buildPdf(costs, await PdfAssets.load()),
      );
    }
    keep(payroll.fileName(ExportFormat.xlsx), buildXlsx(payroll));
    keep(payroll.fileName(ExportFormat.pdf), await buildPdf(payroll, await PdfAssets.load()));
    keep(report.fileName(ExportFormat.pdf), await buildPdf(report, await PdfAssets.load()));
    await store.close(discardPending: false);
  });

  testWidgets('the payroll screen exports what it shows; the menu offers Excel and PDF', (tester) async {
    final store = await pumpMacApp(tester, role: 'superadmin');
    tester.state<DesktopShellState>(find.byType(DesktopShell)).go(DeskSection.payroll);
    await tester.pumpAndSettle();
    final doc = (await tester.state<PayrollScreenState>(find.byType(PayrollScreen)).exportDoc())!;
    expect(doc.title, 'Зарплата студії');
    final monthStart = isoDate(DateTime(DateTime.now().year, DateTime.now().month));
    expect(doc.period, startsWith(formatDateDMY(monthStart)));

    await tester.tap(find.byTooltip('Експорт'));
    await tester.pumpAndSettle();
    expect(find.text('Excel (.xlsx)'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await closeMacApp(tester, store);
  }, variant: mac);
}
