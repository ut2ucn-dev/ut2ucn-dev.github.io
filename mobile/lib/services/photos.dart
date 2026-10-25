import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../desktop/platform.dart';
import '../ui/theme.dart';

/// Asks camera-or-gallery, then returns the picked photo as a JPEG no
/// larger than 900px on its long side — the same size and quality the web
/// version's compressImage() produces, so storage stays small. On the Mac
/// there is no camera to ask about: it opens the file picker straight away.
Future<Uint8List?> pickPhoto(BuildContext context, {String title = 'Фото роботи'}) async {
  if (isAdminDesktop) return _pick(ImageSource.gallery);
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
  return _pick(source);
}

Future<Uint8List?> _pick(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 900,
    maxHeight: 900,
    imageQuality: 75,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  // The Mac's picker ignores maxWidth and imageQuality: shrink here.
  return isAdminDesktop ? shrinkToJpeg(bytes) : bytes;
}

/// The photo's long side down to [maxSide] px, as a JPEG at [quality] —
/// what pickImage() does itself on the phone.
Future<Uint8List> shrinkToJpeg(Uint8List bytes, {int maxSide = 900, int quality = 75}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final scale = math.min(1.0, maxSide / math.max(descriptor.width, descriptor.height));
  final codec = await descriptor.instantiateCodec(
    targetWidth: (descriptor.width * scale).round(),
    targetHeight: (descriptor.height * scale).round(),
  );
  final frame = (await codec.getNextFrame()).image;
  final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
  final out = img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: rgba!.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  frame.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return img.encodeJpg(out, quality: quality);
}
