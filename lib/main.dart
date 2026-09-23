import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'app.dart';
import 'db/app_database.dart';
import 'providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) databaseFactory = databaseFactoryFfiWebNoWebWorker;
  final dbPath = kIsWeb
      ? 'games_news.db'
      : p.join(await getDatabasesPath(), 'games_news.db');

  final database = await AppDatabase.open(dbPath);

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const GamesNewsApp(),
    ),
  );
}
