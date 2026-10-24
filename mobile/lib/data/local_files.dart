import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'local_files_io.dart' if (dart.library.js_interop) 'local_files_web.dart' as impl;

/// Device storage for the offline cache, the outbox and photos taken
/// offline. Files on Android/iOS; memory/localStorage in the web demo.
abstract class LocalFiles {
  static LocalFiles create() => impl.createLocalFiles();

  Future<Object?> readJson(String name);
  Future<void> writeJson(String name, Object? data);
  Future<void> delete(String name);

  /// Stores a JPEG and returns a handle to find it again.
  Future<String> savePhoto(Uint8List bytes);
  Future<Uint8List?> readPhoto(String handle);
  Future<void> deletePhoto(String handle);
  ImageProvider photoImage(String handle);
}
