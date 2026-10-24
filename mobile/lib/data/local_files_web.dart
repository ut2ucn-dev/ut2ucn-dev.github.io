import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'local_files.dart';

LocalFiles createLocalFiles() => _WebLocalFiles();

/// The web build only exists for the demo/preview, so JSON goes to
/// localStorage and photos stay in memory for the session.
class _WebLocalFiles implements LocalFiles {
  final _photos = <String, Uint8List>{};

  @override
  Future<Object?> readJson(String name) async {
    final raw = (await SharedPreferences.getInstance()).getString('file:$name');
    return raw == null ? null : jsonDecode(raw);
  }

  @override
  Future<void> writeJson(String name, Object? data) async {
    await (await SharedPreferences.getInstance()).setString('file:$name', jsonEncode(data));
  }

  @override
  Future<void> delete(String name) async {
    await (await SharedPreferences.getInstance()).remove('file:$name');
  }

  @override
  Future<String> savePhoto(Uint8List bytes) async {
    final id = const Uuid().v4();
    _photos[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List?> readPhoto(String handle) async => _photos[handle];

  @override
  Future<void> deletePhoto(String handle) async => _photos.remove(handle);

  @override
  ImageProvider photoImage(String handle) => MemoryImage(_photos[handle] ?? Uint8List(0));
}
