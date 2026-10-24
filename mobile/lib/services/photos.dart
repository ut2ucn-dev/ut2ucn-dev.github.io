import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ui/theme.dart';

/// Asks camera-or-gallery, then returns the picked photo as a JPEG no
/// larger than 900px on its long side — the same size and quality the web
/// version's compressImage() produces, so storage stays small.
Future<Uint8List?> pickPhoto(BuildContext context, {String title = 'Фото роботи'}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_rounded, color: ctx.c.brandText),
              title: const Text('Зробити фото', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: ctx.c.brandText),
              title: const Text('Вибрати з галереї', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
  if (source == null) return null;
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 900,
    maxHeight: 900,
    imageQuality: 75,
    requestFullMetadata: false,
  );
  return file?.readAsBytes();
}
