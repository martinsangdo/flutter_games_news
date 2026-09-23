import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../models/article.dart';

class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static const _listColumns = [
    'id',
    'source',
    'title',
    'link',
    'pub_date',
    'image_url',
    'categories',
    'is_bookmarked',
  ];

  static Future<AppDatabase> open(String path) async {
    final db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, _) => _createSchema(db),
      onUpgrade: (db, oldVersion, _) async {
        // Version 3 turned the celebrity-news reader into a multi-site games
        // reader: ids are now namespaced per source, so old rows (and their
        // bookmarks) have no place in the new schema.
        if (oldVersion < 3) {
          await db.execute('DROP TABLE IF EXISTS articles');
          await _createSchema(db);
        }
      },
    );
    return AppDatabase._(db);
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE articles (
        id TEXT PRIMARY KEY,
        source TEXT NOT NULL,
        title TEXT,
        link TEXT,
        pub_date TEXT,
        image_url TEXT,
        content_html TEXT,
        categories TEXT DEFAULT '',
        is_bookmarked INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_articles_pub_date ON articles (pub_date DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_articles_source_created ON articles (source, is_bookmarked, created_at)',
    );
  }

  /// Inserts new articles and refreshes existing ones in place, preserving
  /// `is_bookmarked` and `created_at`. Then purges everything beyond the newest
  /// [AppConfig.maxUnbookmarkedArticles] unbookmarked rows *of each source in
  /// [articles]*, so a chatty site cannot push the others out of the cache.
  ///
  /// Update-then-insert is used instead of `ON CONFLICT DO UPDATE` because
  /// older Android system SQLite builds (< 3.24) do not support upserts.
  ///
  /// New rows get `created_at` = their publish time (in SQLite's own
  /// `CURRENT_TIMESTAMP` format). The purge orders by `created_at`, so this makes
  /// it keep the newest *articles*; with insertion time, older pages loaded
  /// later by infinite scroll would look "newer" and evict the real newest.
  ///
  /// Pass `purge: false` for pages loaded by infinite scroll: the purge runs on
  /// the next fresh fetch, as specified.
  Future<void> saveFeed(List<Article> articles, {bool purge = true}) async {
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final article in articles) {
        final values = article.toInsertMap();
        final id = values.remove('id');
        batch.update('articles', values, where: 'id = ?', whereArgs: [id]);
      }
      final updated = await batch.commit();

      final insertBatch = txn.batch();
      for (var i = 0; i < articles.length; i++) {
        if ((updated[i] as int? ?? 0) == 0) {
          insertBatch.insert('articles', {
            ...articles[i].toInsertMap(),
            'created_at': _sqlTimestamp(articles[i].pubDate),
          });
        }
      }
      await insertBatch.commit(noResult: true);

      if (!purge) return;
      for (final source in {for (final a in articles) a.source}) {
        await txn.rawDelete(
          'DELETE FROM articles WHERE is_bookmarked = 0 AND source = ? '
          'AND id NOT IN (SELECT id FROM articles '
          'WHERE is_bookmarked = 0 AND source = ? '
          'ORDER BY created_at DESC LIMIT ${AppConfig.maxUnbookmarkedArticles});',
          [source.name, source.name],
        );
      }
    });
  }

  /// Cached articles of every site, newest first. [since] (an ISO publish
  /// date) hides anything older, which keeps the list a contiguous run: older
  /// stale rows from earlier sessions only appear once infinite scroll reaches
  /// them, instead of shifting the list when a page fills the gap above them.
  Future<List<Article>> feed({String? since}) async {
    final rows = await _db.query(
      'articles',
      columns: _listColumns,
      where: since == null ? null : 'pub_date >= ?',
      whereArgs: since == null ? null : [since],
      orderBy: 'pub_date DESC',
    );
    return rows.map(Article.fromMap).toList(growable: false);
  }

  Future<Article?> article(String id) async {
    final rows = await _db.query(
      'articles',
      columns: _listColumns,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Article.fromMap(rows.first);
  }

  /// Newest cached articles other than [excludeId]: the candidate pool for
  /// related-story ranking.
  Future<List<Article>> recent({
    required String excludeId,
    int limit = 200,
  }) async {
    final rows = await _db.query(
      'articles',
      columns: _listColumns,
      where: 'id != ?',
      whereArgs: [excludeId],
      orderBy: 'pub_date DESC',
      limit: limit,
    );
    return rows.map(Article.fromMap).toList(growable: false);
  }

  Future<List<Article>> bookmarked() async {
    final rows = await _db.query(
      'articles',
      columns: _listColumns,
      where: 'is_bookmarked = 1',
      orderBy: 'pub_date DESC',
    );
    return rows.map(Article.fromMap).toList(growable: false);
  }

  Future<Set<String>> bookmarkedIds() async {
    final rows = await _db.query(
      'articles',
      columns: ['id'],
      where: 'is_bookmarked = 1',
    );
    return {for (final row in rows) row['id'] as String};
  }

  Future<String> contentHtml(String id) async {
    final rows = await _db.query(
      'articles',
      columns: ['content_html'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? '' : (rows.first['content_html'] as String?) ?? '';
  }

  Future<void> setBookmarked(String id, {required bool value}) => _db.update(
    'articles',
    {'is_bookmarked': value ? 1 : 0},
    where: 'id = ?',
    whereArgs: [id],
  );
}

String _sqlTimestamp(String isoDate) {
  final date = (DateTime.tryParse(isoDate) ?? DateTime.now()).toUtc();
  return date.toIso8601String().substring(0, 19).replaceFirst('T', ' ');
}
