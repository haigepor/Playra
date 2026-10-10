import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

late Box<dynamic> _files;
late Box<int> _modified;

/// 文件存在浏览器 IndexedDB 中，沿用原有规则、下载和同步代码的文件接口。
Future<void> initializeBrowserFiles() async {
  _files = await Hive.openBox<dynamic>('browser-files-v1');
  _modified = await Hive.openBox<int>('browser-files-metadata-v1');
}

String _normalize(String value) =>
    p.posix.normalize('/${value.replaceAll('\\', '/')}');
String _directoryKey(String value) => '${_normalize(value)}/';

class File implements io.File {
  File(String value) : path = _normalize(value);
  @override
  final String path;
  @override
  Uri get uri => Uri.file(path);
  @override
  File get absolute => this;
  @override
  Directory get parent => Directory(p.posix.dirname(path));
  @override
  bool get isAbsolute => true;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('浏览器文件操作不支持 ${invocation.memberName}');
  @override
  bool existsSync() => _files.containsKey(path);
  @override
  Future<bool> exists() async => existsSync();
  @override
  Uint8List readAsBytesSync() {
    final value = _files.get(path);
    if (value is! List) throw io.FileSystemException('File not found', path);
    return Uint8List.fromList(value.cast<int>());
  }

  @override
  Future<Uint8List> readAsBytes() async => readAsBytesSync();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(readAsBytesSync());
  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      encoding.decode(readAsBytesSync());
  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) async =>
      const LineSplitter().convert(await readAsString(encoding: encoding));
  @override
  int lengthSync() => readAsBytesSync().length;
  @override
  Future<int> length() async => lengthSync();
  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    io.FileMode mode = io.FileMode.write,
    bool flush = false,
  }) async {
    await parent.create(recursive: true);
    final append =
        mode == io.FileMode.append || mode == io.FileMode.writeOnlyAppend;
    final content = append && existsSync()
        ? [...readAsBytesSync(), ...bytes]
        : bytes;
    await _files.put(path, Uint8List.fromList(content));
    await _modified.put(path, DateTime.now().millisecondsSinceEpoch);
    return this;
  }

  @override
  Future<File> writeAsString(
    String contents, {
    io.FileMode mode = io.FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => writeAsBytes(encoding.encode(contents), mode: mode, flush: flush);
  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    if (exclusive && existsSync()) {
      throw io.FileSystemException('File exists', path);
    }
    if (!existsSync()) await writeAsBytes([]);
    return this;
  }

  @override
  Future<File> delete({bool recursive = false}) async {
    if (!existsSync()) throw io.FileSystemException('File not found', path);
    await _files.delete(path);
    await _modified.delete(path);
    return this;
  }

  @override
  Future<File> copy(String newPath) =>
      File(newPath).writeAsBytes(readAsBytesSync());
  @override
  Future<File> rename(String newPath) async {
    final destination = await copy(newPath);
    if (destination.path != path) await delete();
    return destination;
  }

  @override
  Future<io.RandomAccessFile> open({
    io.FileMode mode = io.FileMode.read,
  }) async {
    if (mode == io.FileMode.read && !existsSync()) {
      throw io.FileSystemException('File not found', path);
    }
    final append =
        mode == io.FileMode.append || mode == io.FileMode.writeOnlyAppend;
    final bytes = (mode == io.FileMode.read || append) && existsSync()
        ? readAsBytesSync()
        : <int>[];
    return _BrowserHandle(
      this,
      bytes.toList(),
      mode,
      append ? bytes.length : 0,
    );
  }

  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    final bytes = readAsBytesSync();
    yield bytes.sublist(start ?? 0, end ?? bytes.length);
  }

  @override
  io.IOSink openWrite({
    io.FileMode mode = io.FileMode.write,
    Encoding encoding = utf8,
  }) => io.IOSink(_FileConsumer(this, mode), encoding: encoding);
  @override
  Future<io.FileStat> stat() async => _BrowserStat(
    existsSync()
        ? io.FileSystemEntityType.file
        : io.FileSystemEntityType.notFound,
    existsSync() ? lengthSync() : 0,
    _modified.get(path),
  );
  @override
  Future<DateTime> lastModified() async => (await stat()).modified;
}

class Directory implements io.Directory {
  Directory(String value) : path = _normalize(value);
  @override
  final String path;
  @override
  Uri get uri => Uri.directory(path);
  @override
  Directory get absolute => this;
  @override
  Directory get parent => Directory(p.posix.dirname(path));
  @override
  bool get isAbsolute => true;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('浏览器目录操作不支持 ${invocation.memberName}');
  @override
  bool existsSync() => path == '/' || _files.containsKey(_directoryKey(path));
  @override
  Future<bool> exists() async => existsSync();
  @override
  Future<Directory> create({bool recursive = false}) async {
    if (path == '/') return this;
    if (recursive) await parent.create(recursive: true);
    if (!parent.existsSync()) {
      throw io.FileSystemException('Parent directory not found', path);
    }
    await _files.put(_directoryKey(path), true);
    await _modified.put(
      _directoryKey(path),
      DateTime.now().millisecondsSinceEpoch,
    );
    return this;
  }

  @override
  Future<Directory> createTemp([String? prefix]) async {
    await create(recursive: true);
    return Directory(
      '$path/${prefix ?? ''}${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);
  }

  @override
  List<io.FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) {
    final prefix = path == '/' ? '/' : '$path/';
    final result = <io.FileSystemEntity>[];
    for (final key in _files.keys.cast<String>()) {
      if (!key.startsWith(prefix) || key == _directoryKey(path)) continue;
      final clean = key.endsWith('/') ? key.substring(0, key.length - 1) : key;
      if (!recursive && clean.substring(prefix.length).contains('/')) continue;
      result.add(key.endsWith('/') ? Directory(clean) : File(key));
    }
    return result;
  }

  @override
  Stream<io.FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => Stream.fromIterable(
    listSync(recursive: recursive, followLinks: followLinks),
  );
  @override
  Future<Directory> delete({bool recursive = false}) async {
    final entries = listSync(recursive: true);
    if (!recursive && entries.isNotEmpty) {
      throw io.FileSystemException('Directory not empty', path);
    }
    await _files.deleteAll(
      entries.map(
        (entry) => entry is Directory ? _directoryKey(entry.path) : entry.path,
      ),
    );
    await _modified.deleteAll(
      entries.map(
        (entry) => entry is Directory ? _directoryKey(entry.path) : entry.path,
      ),
    );
    await _files.delete(_directoryKey(path));
    await _modified.delete(_directoryKey(path));
    return this;
  }

  @override
  Future<io.FileStat> stat() async => _BrowserStat(
    existsSync()
        ? io.FileSystemEntityType.directory
        : io.FileSystemEntityType.notFound,
    0,
    _modified.get(_directoryKey(path)),
  );
}

class _BrowserHandle implements io.RandomAccessFile {
  _BrowserHandle(this.file, this.bytes, this.mode, this.offset);
  final File file;
  final List<int> bytes;
  final io.FileMode mode;
  int offset;
  bool closed = false;
  void _check() {
    if (closed) throw io.FileSystemException('File handle closed', file.path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('浏览器文件句柄操作不支持 ${invocation.memberName}');
  @override
  String get path => file.path;
  @override
  Future<io.RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    _check();
    if (mode == io.FileMode.read) {
      throw io.FileSystemException('File is read only', path);
    }
    final content = buffer.sublist(start, end);
    while (bytes.length < offset + content.length) {
      bytes.add(0);
    }
    bytes.setRange(offset, offset + content.length, content);
    offset += content.length;
    return this;
  }

  @override
  Future<io.RandomAccessFile> setPosition(int position) async {
    _check();
    if (position < 0) throw RangeError.value(position);
    offset = position;
    return this;
  }

  @override
  Future<int> position() async {
    _check();
    return offset;
  }

  @override
  Future<int> length() async {
    _check();
    return bytes.length;
  }

  @override
  Future<Uint8List> read(int count) async {
    _check();
    final end = (offset + count).clamp(0, bytes.length);
    final result = Uint8List.fromList(bytes.sublist(offset, end));
    offset = end;
    return result;
  }

  @override
  Future<io.RandomAccessFile> flush() async {
    _check();
    if (mode != io.FileMode.read) await file.writeAsBytes(bytes);
    return this;
  }

  @override
  Future<void> close() async {
    _check();
    await flush();
    closed = true;
  }
}

class _BrowserStat implements io.FileStat {
  _BrowserStat(this.type, this.size, this.modifiedMilliseconds);
  final int? modifiedMilliseconds;
  @override
  final io.FileSystemEntityType type;
  @override
  final int size;
  @override
  int get mode => 0;
  @override
  DateTime get modified =>
      DateTime.fromMillisecondsSinceEpoch(modifiedMilliseconds ?? 0);
  @override
  DateTime get changed => modified;
  @override
  DateTime get accessed => modified;
  @override
  String modeString() => 'rw-------';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FileConsumer implements StreamConsumer<List<int>> {
  _FileConsumer(this.file, this.mode);
  final File file;
  final io.FileMode mode;
  final bytes = BytesBuilder(copy: false);
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      bytes.add(chunk);
    }
  }

  @override
  Future<void> close() async {
    await file.writeAsBytes(bytes.takeBytes(), mode: mode);
  }
}
