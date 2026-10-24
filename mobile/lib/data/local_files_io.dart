import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'local_files.dart';

LocalFiles createLocalFiles() => _IoLocalFiles();

class _IoLocalFiles implements LocalFiles {
  Directory? _dir;

  Future<Directory> _root() async {
    return _dir ??= await getApplicationSupportDirectory();
  }

  Future<File> _file(String name) async => File('${(await _root()).path}/$name');

  @override
  Future<Object?> readJson(String name) async {
    final f = await _file(name);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeJson(String name, Object? data) async {
    final f = await _file(name);
    // Write-then-rename so a crash mid-write never leaves half a file.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String name) async {
    final f = await _file(name);
    if (await f.exists()) await f.delete();
  }

  Future<Directory> _photos() async {
    final d = Directory('${(await _root()).path}/pending_photos');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  @override
  Future<String> savePhoto(Uint8List bytes) async {
    final f = File('${(await _photos()).path}/${const Uuid().v4()}.jpg');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  @override
  Future<Uint8List?> readPhoto(String handle) async {
    final f = File(handle);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> deletePhoto(String handle) async {
    final f = File(handle);
    if (await f.exists()) await f.delete();
  }

  @override
  ImageProvider photoImage(String handle) => FileImage(File(handle));
}
