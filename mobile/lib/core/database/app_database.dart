import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:familymed/core/database/tables/cached_doses.dart';
import 'package:familymed/core/database/tables/cached_today_members.dart';
import 'package:familymed/core/database/tables/sync_operations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: <Type>[
    CachedTodayMembers,
    CachedDoses,
    SyncOperations,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator migrator) => migrator.createAll(),
        onUpgrade: (Migrator migrator, int from, int to) async {
          if (from < 2) {
            await migrator.createTable(cachedTodayMembers);
            await migrator.createTable(cachedDoses);
            await migrator.createTable(syncOperations);
          }
          if (from < 3) {
            await migrator.addColumn(cachedTodayMembers, cachedTodayMembers.userId);
            await migrator.addColumn(cachedDoses, cachedDoses.userId);
            await migrator.addColumn(syncOperations, syncOperations.userId);
          }
        },
      );
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    return NativeDatabase(File(p.join(directory.path, 'familymed.sqlite')));
  });
}
