import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../desktop/platform.dart';
import 'export_doc.dart';
import 'pdf_writer.dart';
import 'xlsx_writer.dart';

/// A screen whose report can be exported (payroll, studio report, print
/// costs); the Mac's File menu reaches it through its state.
mixin ExportableScreen<T extends StatefulWidget> on State<T> {
  /// The report as it is on screen now, or null while it is loading.
  Future<ExportDoc?> exportDoc();

  Future<void> exportAs(ExportFormat format) async {
    final doc = await exportDoc();
    if (doc == null || !mounted) return;
    await exportDocument(context, doc, format);
  }
}

/// Builds the file and hands it over: "Save as…" on the Mac (then
/// "Відкрити" in the snackbar), the share sheet on a phone (to Files,
/// Telegram, mail…), a download in a browser.
Future<void> exportDocument(BuildContext context, ExportDoc doc, ExportFormat format) async {
  final messenger = ScaffoldMessenger.of(context);
  final Uint8List bytes;
  try {
    bytes = format == ExportFormat.xlsx ? buildXlsx(doc) : await buildPdf(doc, await PdfAssets.load());
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Не вдалося сформувати файл: $e')));
    return;
  }
  final name = doc.fileName(format);
  final file = XFile.fromData(bytes, mimeType: format.mime, name: name);
  try {
    if (kIsWeb) {
      await file.saveTo(name);
      return;
    }
    if (isAdminDesktop || defaultTargetPlatform == TargetPlatform.macOS) {
      final where = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: [
          XTypeGroup(label: format.label, extensions: [format.extension], mimeTypes: [format.mime]),
        ],
      );
      if (where == null) return;
      await file.saveTo(where.path);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            width: 480,
            content: Text('Збережено: ${where.path.split('/').last}'),
            action: SnackBarAction(label: 'Відкрити', onPressed: () => launchUrl(Uri.file(where.path))),
          ),
        );
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$name';
    await file.saveTo(path);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: format.mime, name: name)],
        subject: doc.title,
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Не вдалося зберегти файл: $e')));
  }
}

/// The "export" button for a report's app bar: Excel or PDF.
class ExportButton extends StatelessWidget {
  const ExportButton({super.key, required this.onExport});
  final void Function(ExportFormat format)? onExport;

  @override
  Widget build(BuildContext context) => PopupMenuButton<ExportFormat>(
    tooltip: 'Експорт',
    enabled: onExport != null,
    icon: const Icon(Icons.ios_share_rounded),
    onSelected: onExport,
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: ExportFormat.xlsx,
        child: ListTile(leading: Icon(Icons.table_view_rounded), title: Text('Excel (.xlsx)')),
      ),
      PopupMenuItem(
        value: ExportFormat.pdf,
        child: ListTile(leading: Icon(Icons.picture_as_pdf_rounded), title: Text('PDF')),
      ),
    ],
  );
}
