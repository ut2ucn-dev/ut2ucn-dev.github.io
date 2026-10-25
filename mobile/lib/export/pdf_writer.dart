import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../util/dates.dart';
import '../util/domain.dart';
import 'export_doc.dart';

/// Fonts and logo for PDFs: the app's own Exo 2 (it has Cyrillic, the PDF
/// base fonts don't) and the studio robot.
class PdfAssets {
  const PdfAssets({required this.regular, required this.bold, this.logo});
  final ByteData regular;
  final ByteData bold;
  final Uint8List? logo;

  static Future<PdfAssets> load() async => PdfAssets(
    regular: await rootBundle.load('assets/fonts/Exo2-400.ttf'),
    bold: await rootBundle.load('assets/fonts/Exo2-700.ttf'),
    logo: (await rootBundle.load('assets/brand/robot-light.png')).buffer.asUint8List(),
  );
}

// The web's light-theme colours.
const _ink = PdfColor.fromInt(0xFF171923);
const _inkSoft = PdfColor.fromInt(0xFF6B7080);
const _brandText = PdfColor.fromInt(0xFF4B3FCB);
const _brandSoft = PdfColor.fromInt(0xFFEFEDFC);
const _paper = PdfColor.fromInt(0xFFF6F6FB);
const _line = PdfColor.fromInt(0xFFE7E8F1);

/// Writes [doc] as an A4 PDF (landscape when a table is wide): the robot
/// and the report's title on top, the headline figures, then every table
/// with its header repeated on each page, and page numbers below.
Future<Uint8List> buildPdf(ExportDoc doc, PdfAssets assets) async {
  final theme = pw.ThemeData.withFont(base: pw.Font.ttf(assets.regular), bold: pw.Font.ttf(assets.bold));
  final wide = doc.tables.any((t) => t.columns.length > 6);
  final pdf = pw.Document(title: doc.title, author: 'Stemik', creator: 'Stemik');
  final logo = assets.logo == null ? null : pw.MemoryImage(assets.logo!);
  final made = DateTime.now();

  pdf.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: (wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4).copyWith(
        marginLeft: 32,
        marginRight: 32,
        marginTop: 28,
        marginBottom: 28,
      ),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text('${doc.title} · ${doc.period}', style: const pw.TextStyle(fontSize: 8, color: _inkSoft)),
            ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Stemik · сформовано ${formatDateDMY(isoDate(made))} ${minutesToTime(made.hour * 60 + made.minute)}',
            style: const pw.TextStyle(fontSize: 8, color: _inkSoft),
          ),
          pw.Text(
            'Сторінка ${context.pageNumber} з ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _inkSoft),
          ),
        ],
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) pw.Image(logo, width: 40),
            if (logo != null) pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    doc.title,
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _ink),
                  ),
                  pw.Text(doc.period, style: const pw.TextStyle(fontSize: 11, color: _inkSoft)),
                ],
              ),
            ),
            pw.Text(
              'Stemik',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _brandText),
            ),
          ],
        ),
        if (doc.summary.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, value) in doc.summary)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: pw.BoxDecoration(
                    color: _paper,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: _line),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _inkSoft)),
                    ],
                  ),
                ),
            ],
          ),
        ],
        for (final t in doc.tables) ..._table(t),
      ],
    ),
  );
  return pdf.save();
}

List<pw.Widget> _table(ExportTable t) {
  final title = pw.Padding(
    padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
    child: pw.Text(
      t.title,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _brandText),
    ),
  );
  if (t.newPage && t.rows.isNotEmpty) {
    return [
      pw.NewPage(),
      ..._table(ExportTable(title: t.title, columns: t.columns, rows: t.rows, total: t.total, empty: t.empty)),
    ];
  }
  if (t.rows.isEmpty) {
    return [title, pw.Text(t.empty ?? 'Немає даних.', style: const pw.TextStyle(fontSize: 10, color: _inkSoft))];
  }
  pw.Widget cell(ExportColumn col, Object? v, {bool bold = false, bool header = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(
      header ? col.title : formatCell(col.kind, v),
      textAlign: col.numeric ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: header ? 8.5 : 9,
        fontWeight: bold || header ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: header ? _brandText : _ink,
      ),
    ),
  );
  return [
    title,
    pw.Table(
      columnWidths: {for (final (i, c) in t.columns.indexed) i: pw.FlexColumnWidth(c.width)},
      border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _brandSoft),
          children: [for (final c in t.columns) cell(c, null, header: true)],
        ),
        for (final (i, r) in t.rows.indexed)
          pw.TableRow(
            decoration: i.isOdd ? const pw.BoxDecoration(color: _paper) : null,
            children: [for (final (j, c) in t.columns.indexed) cell(c, j < r.length ? r[j] : null)],
          ),
        if (t.total != null)
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              color: _brandSoft,
              border: pw.Border(top: pw.BorderSide(color: _brandText, width: 1)),
            ),
            children: [
              for (final (j, c) in t.columns.indexed) cell(c, j < t.total!.length ? t.total![j] : null, bold: true),
            ],
          ),
      ],
    ),
  ];
}

/// A cell as text, the way the app shows it.
String formatCell(ColKind kind, Object? v) {
  if (v == null) return '';
  // "Разом" in a date column stays text.
  if (v is String && (kind != ColKind.date || DateTime.tryParse(v) == null)) return v;
  switch (kind) {
    case ColKind.money:
      return formatMoney(v as num);
    case ColKind.integer:
      return '${(v as num).round()}';
    case ColKind.decimal:
      return formatGrams(v as num);
    case ColKind.date:
      return formatDateDMY('$v');
    case ColKind.text:
      return '$v';
  }
}
