/// A report ready to export: the same content becomes an Excel workbook
/// (a sheet per table, real numbers and dates) or a PDF (tables one after
/// another). The builders in reports.dart fill it from what the screens
/// show, so the files always match the screen.
library;

enum ExportFormat {
  xlsx('Excel', 'xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  pdf('PDF', 'pdf', 'application/pdf');

  const ExportFormat(this.label, this.extension, this.mime);
  final String label;
  final String extension;
  final String mime;
}

enum ColKind { text, money, integer, decimal, date }

class ExportColumn {
  const ExportColumn(this.title, {this.kind = ColKind.text, this.width = 14});
  final String title;
  final ColKind kind;

  /// In Excel characters; the PDF shares the page out in proportion.
  final double width;

  bool get numeric => kind == ColKind.money || kind == ColKind.integer || kind == ColKind.decimal;
}

/// Cells are String, num (money, integer, decimal), an ISO date String for
/// [ColKind.date], or null.
class ExportTable {
  const ExportTable({
    required this.title,
    required this.columns,
    required this.rows,
    this.total,
    this.empty,
    this.newPage = false,
  });
  final String title;
  final List<ExportColumn> columns;
  final List<List<Object?>> rows;

  /// The "Разом" row, under the data.
  final List<Object?>? total;

  /// Said instead of an empty table.
  final String? empty;

  /// In a PDF, starts on a page of its own (a long, wide table after
  /// short ones, so its title isn't left alone at the foot of a page).
  final bool newPage;
}

class ExportDoc {
  const ExportDoc({
    required this.title,
    required this.period,
    required this.fileStem,
    this.summary = const [],
    required this.tables,
  });

  /// "Зарплата студії".
  final String title;

  /// "01.10.2026 – 25.10.2026".
  final String period;

  /// The file name without extension.
  final String fileStem;

  /// Headline figures, label → value as shown.
  final List<(String, String)> summary;
  final List<ExportTable> tables;

  String fileName(ExportFormat f) => '${fileStem.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')}.${f.extension}';
}
