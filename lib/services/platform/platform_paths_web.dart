import 'browser_file_system.dart';

Future<Directory> getApplicationSupportDirectory() async =>
    Directory('/kazumi');
Future<Directory> getTemporaryDirectory() async => Directory('/kazumi/tmp');
Future<Directory> getApplicationDocumentsDirectory() async =>
    Directory('/kazumi/documents');
Future<Directory> getApplicationCacheDirectory() async =>
    Directory('/kazumi/cache');
Future<Directory?> getDownloadsDirectory() async =>
    Directory('/kazumi/downloads');
