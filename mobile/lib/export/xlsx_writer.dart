import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'export_doc.dart';

/// Writes [doc] as an .xlsx workbook: a sheet per table with the report's
/// title and period on top, the headline figures on the first sheet, a
/// frozen, filterable header row, money as numbers in "грн", dates as real
/// dates, and a bold "Разом" row. Plain Office Open XML in a zip — no
/// spreadsheet library needed.
Uint8List buildXlsx(ExportDoc doc) {
  final names = <String>[];
  final sheets = <String>[];
  for (final (i, t) in doc.tables.indexed) {
    names.add(_sheetName(t.title, names));
    sheets.add(_sheet(doc, t, first: i == 0));
  }

  final files = <String, String>{
    '[Content_Types].xml': _contentTypes(sheets.length),
    '_rels/.rels': _rootRels,
    'docProps/app.xml': _appProps,
    'docProps/core.xml': _coreProps(doc.title),
    'xl/workbook.xml': _workbook(names),
    'xl/_rels/workbook.xml.rels': _workbookRels(sheets.length),
    'xl/styles.xml': _styles,
    for (final (i, s) in sheets.indexed) 'xl/worksheets/sheet${i + 1}.xml': s,
  };
  final archive = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

// Style indexes into cellXfs below.
const _sDefault = 0, _sHeader = 1, _sMoney = 2, _sTotalMoney = 3, _sTitle = 4, _sTotalText = 5;
const _sInt = 6, _sDecimal = 7, _sDate = 8, _sMuted = 9, _sTotalInt = 10, _sTotalDecimal = 11, _sSummary = 12;

String _sheet(ExportDoc doc, ExportTable t, {required bool first}) {
  final rows = StringBuffer();
  var r = 0;
  void row(List<String> cells) {
    r++;
    rows.write('<row r="$r">${cells.join()}</row>');
  }

  final cols = t.columns.length;
  row([_text(r + 1, 0, '${doc.title} — ${t.title}', _sTitle)]);
  row([_text(r + 1, 0, doc.period, _sMuted)]);
  if (first) {
    for (final (label, value) in doc.summary) {
      row([_text(r + 1, 0, label, _sMuted), _text(r + 1, 1, value, _sSummary)]);
    }
  }
  row([]);
  final headerRow = r + 1;
  row([for (final (c, col) in t.columns.indexed) _text(headerRow, c, col.title, _sHeader)]);
  if (t.rows.isEmpty && t.empty != null) row([_text(r + 1, 0, t.empty!, _sMuted)]);
  for (final values in t.rows) {
    final n = r + 1;
    row([for (final (c, col) in t.columns.indexed) _cell(n, c, col.kind, c < values.length ? values[c] : null)]);
  }
  if (t.total != null) {
    final n = r + 1;
    row([
      for (final (c, col) in t.columns.indexed)
        _cell(n, c, col.kind, c < t.total!.length ? t.total![c] : null, total: true),
    ]);
  }

  final widths = [
    for (final (c, col) in t.columns.indexed)
      '<col min="${c + 1}" max="${c + 1}" width="${col.width}" customWidth="1"/>',
  ].join();
  final lastCol = _col(cols - 1);
  final filter = t.rows.isEmpty ? '' : '<autoFilter ref="A$headerRow:$lastCol${headerRow + t.rows.length}"/>';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
      '<sheetViews><sheetView workbookViewId="0">'
      '<pane ySplit="$headerRow" topLeftCell="A${headerRow + 1}" activePane="bottomLeft" state="frozen"/>'
      '</sheetView></sheetViews>'
      '<cols>$widths</cols>'
      '<sheetData>$rows</sheetData>'
      '$filter'
      '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>'
      '<pageSetup orientation="${cols > 6 ? 'landscape' : 'portrait'}" fitToWidth="1" fitToHeight="0"/>'
      '</worksheet>';
}

String _cell(int row, int col, ColKind kind, Object? v, {bool total = false}) {
  if (v == null) return '';
  // "Разом" in a date column stays text.
  if (v is String && (kind != ColKind.date || DateTime.tryParse(v) == null)) {
    return _text(row, col, v, total ? _sTotalText : _sDefault);
  }
  switch (kind) {
    case ColKind.money:
      return _num(row, col, v as num, total ? _sTotalMoney : _sMoney);
    case ColKind.integer:
      return _num(row, col, v as num, total ? _sTotalInt : _sInt);
    case ColKind.decimal:
      return _num(row, col, v as num, total ? _sTotalDecimal : _sDecimal);
    case ColKind.date:
      final d = DateTime.tryParse('$v');
      if (d == null) return _text(row, col, '$v', _sDefault);
      // Days since 1899-12-30, Excel's day zero.
      final serial = DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1899, 12, 30)).inDays;
      return _num(row, col, serial, _sDate);
    case ColKind.text:
      return _text(row, col, '$v', total ? _sTotalText : _sDefault);
  }
}

String _ref(int row, int col) => '${_col(col)}$row';

String _col(int c) {
  var n = c + 1;
  var s = '';
  while (n > 0) {
    final m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

String _text(int row, int col, String v, int style) =>
    '<c r="${_ref(row, col)}" t="inlineStr" s="$style"><is><t xml:space="preserve">${_esc(v)}</t></is></c>';

String _num(int row, int col, num v, int style) => '<c r="${_ref(row, col)}" s="$style"><v>$v</v></c>';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Control characters other than tab and newlines aren't allowed in XML.
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

/// Unique, at most 31 characters, none of []:*?/\.
String _sheetName(String title, List<String> taken) {
  var base = title.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (base.isEmpty) base = 'Аркуш';
  if (base.length > 31) base = base.substring(0, 31);
  var name = base;
  for (var i = 2; taken.contains(name); i++) {
    final suffix = ' ($i)';
    name = '${base.substring(0, base.length.clamp(0, 31 - suffix.length))}$suffix';
  }
  return name;
}

String _contentTypes(int sheets) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '${[for (var i = 1; i <= sheets; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
    '<Override PartName="/xl/styles.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    '<Override PartName="/docProps/app.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
    '</Types>';

const _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '<Relationship Id="rId2" '
    'Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" '
    'Target="docProps/core.xml"/>'
    '<Relationship Id="rId3" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" '
    'Target="docProps/app.xml"/>'
    '</Relationships>';

const _appProps =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
    '<Application>Stemik</Application></Properties>';

String _coreProps(String title) {
  final now = DateTime.now().toUtc().toIso8601String().split('.').first;
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${_esc(title)}</dc:title><dc:creator>Stemik</dc:creator>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">${now}Z</dcterms:created>'
      '</cp:coreProperties>';
}

String _workbook(List<String> names) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
    '${[for (final (i, n) in names.indexed) '<sheet name="${_esc(n)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
    '</sheets></workbook>';

String _workbookRels(int sheets) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${[for (var i = 1; i <= sheets; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
    '<Relationship Id="rId${sheets + 1}" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

// Fonts: 0 normal, 1 bold, 2 title, 3 muted. Fills: 2 = header (the
// studio's brand-soft violet), 3 = totals. Number formats: 164 money,
// 165 date, 166 one decimal.
const _styles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="3">'
    '<numFmt numFmtId="164" formatCode="#,##0.00&quot; грн&quot;"/>'
    '<numFmt numFmtId="165" formatCode="dd.mm.yyyy"/>'
    '<numFmt numFmtId="166" formatCode="#,##0.0"/>'
    '</numFmts>'
    '<fonts count="4">'
    '<font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="14"/><color rgb="FF4B3FCB"/><name val="Calibri"/></font>'
    '<font><sz val="10"/><color rgb="FF6B7080"/><name val="Calibri"/></font>'
    '</fonts>'
    '<fills count="4">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFEFEDFC"/><bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFF6F6FB"/><bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="2">'
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
    '<border><left/><right/><top style="thin"><color rgb="FFD7D9E8"/></top><bottom/><diagonal/></border>'
    '</borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="13">'
    // 0 default
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    // 1 header
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1">'
    '<alignment wrapText="1" vertical="center"/></xf>'
    // 2 money
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    // 3 total money
    '<xf numFmtId="164" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" '
    'applyFill="1" applyBorder="1"/>'
    // 4 title
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    // 5 total text
    '<xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>'
    // 6 integer
    '<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    // 7 decimal
    '<xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    // 8 date
    '<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1">'
    '<alignment horizontal="left"/></xf>'
    // 9 muted
    '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    // 10 total integer
    '<xf numFmtId="3" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" '
    'applyFill="1" applyBorder="1"/>'
    // 11 total decimal
    '<xf numFmtId="166" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" '
    'applyFill="1" applyBorder="1"/>'
    // 12 summary value
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';
