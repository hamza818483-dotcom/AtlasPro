import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../core/constants.dart';
import 'auth_service.dart';

class OfflineService {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      p.join(dbPath, 'atlas_offline.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS cached_pdfs (
            id INTEGER PRIMARY KEY,
            chapter_id INTEGER,
            title TEXT,
            r2_url TEXT,
            local_path TEXT,
            page_count INTEGER DEFAULT 0,
            cached_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS cached_mcqs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pdf_id INTEGER,
            page_number INTEGER,
            type TEXT DEFAULT 'standard',
            question TEXT,
            option_a TEXT, option_b TEXT,
            option_c TEXT, option_d TEXT,
            correct_answer TEXT,
            explanation TEXT DEFAULT '',
            cached_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS cached_subjects (
            id INTEGER PRIMARY KEY,
            name TEXT, icon TEXT, description TEXT,
            cached_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS cached_chapters (
            id INTEGER PRIMARY KEY,
            subject_id INTEGER,
            name TEXT, order_index INTEGER,
            cached_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS pending_sync (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT,
            payload TEXT,
            created_at INTEGER
          )
        ''');
      },
    );
  }

  // ─── SUBJECTS & CHAPTERS ────────────────────────────────
  static Future<void> cacheSubjects(List<Map<String, dynamic>> subjects) async {
    final database = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = database.batch();
    for (final s in subjects) {
      batch.insert('cached_subjects', {
        'id': s['id'], 'name': s['name'],
        'icon': s['icon'], 'description': s['description'] ?? '',
        'cached_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getCachedSubjects() async {
    final database = await db;
    return database.query('cached_subjects', orderBy: 'id ASC');
  }

  static Future<void> cacheChapters(
      int subjectId, List<Map<String, dynamic>> chapters) async {
    final database = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = database.batch();
    for (final c in chapters) {
      batch.insert('cached_chapters', {
        'id': c['id'], 'subject_id': subjectId,
        'name': c['name'], 'order_index': c['order_index'] ?? 0,
        'cached_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getCachedChapters(int subjectId) async {
    final database = await db;
    return database.query('cached_chapters',
        where: 'subject_id=?',
        whereArgs: [subjectId],
        orderBy: 'order_index ASC');
  }

  // ─── PDF CACHING ────────────────────────────────────────
  static Future<String?> getCachedPdfPath(int pdfId) async {
    final database = await db;
    final rows = await database.query('cached_pdfs',
        where: 'id=?', whereArgs: [pdfId], limit: 1);
    if (rows.isEmpty) return null;
    final localPath = rows.first['local_path'] as String?;
    if (localPath == null) return null;
    if (await File(localPath).exists()) return localPath;
    return null;
  }

  static Future<String?> downloadAndCachePdf(
      int pdfId, String r2Url, String title) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final localPath = p.join(dir.path, 'pdfs', 'pdf_$pdfId.pdf');
      await Directory(p.dirname(localPath)).create(recursive: true);

      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/pdf/download/$pdfId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        await File(localPath).writeAsBytes(res.bodyBytes);
        final database = await db;
        await database.insert('cached_pdfs', {
          'id': pdfId,
          'title': title,
          'r2_url': r2Url,
          'local_path': localPath,
          'cached_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        return localPath;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> isPdfCached(int pdfId) async {
    final path = await getCachedPdfPath(pdfId);
    return path != null;
  }

  static Future<List<Map<String, dynamic>>> getCachedPdfs() async {
    final database = await db;
    return database.query('cached_pdfs');
  }

  static Future<void> deleteCachedPdf(int pdfId) async {
    final path = await getCachedPdfPath(pdfId);
    if (path != null) {
      try { await File(path).delete(); } catch (_) {}
    }
    final database = await db;
    await database.delete('cached_pdfs', where: 'id=?', whereArgs: [pdfId]);
  }

  // ─── MCQ CACHING ────────────────────────────────────────
  static Future<void> cacheMcqs(
      int pdfId, int pageNumber, String type, List<Map<String, dynamic>> mcqs) async {
    final database = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Keep max 2 sets
    final existing = await database.query('cached_mcqs',
        where: 'pdf_id=? AND page_number=? AND type=?',
        whereArgs: [pdfId, pageNumber, type]);
    if (existing.length >= 20) return; // 2 sets of 10
    final batch = database.batch();
    for (final m in mcqs) {
      batch.insert('cached_mcqs', {
        'pdf_id': pdfId, 'page_number': pageNumber, 'type': type,
        'question': m['question'] ?? '',
        'option_a': m['option_a'] ?? '', 'option_b': m['option_b'] ?? '',
        'option_c': m['option_c'] ?? '', 'option_d': m['option_d'] ?? '',
        'correct_answer': m['correct_answer'] ?? 'A',
        'explanation': m['explanation'] ?? '',
        'cached_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getCachedMcqs(
      int pdfId, int pageNumber, String type) async {
    final database = await db;
    final all = await database.query('cached_mcqs',
        where: 'pdf_id=? AND page_number=? AND type=?',
        whereArgs: [pdfId, pageNumber, type]);
    return all;
  }

  static Future<bool> hasCachedMcqs(int pdfId, int pageNumber, String type) async {
    final mcqs = await getCachedMcqs(pdfId, pageNumber, type);
    return mcqs.isNotEmpty;
  }

  // ─── PENDING SYNC ───────────────────────────────────────
  static Future<void> addPendingSync(String type, Map<String, dynamic> payload) async {
    final database = await db;
    await database.insert('pending_sync', {
      'type': type,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<void> syncPending() async {
    final database = await db;
    final pending = await database.query('pending_sync', orderBy: 'created_at ASC');
    final token = await AuthService.getToken();

    for (final row in pending) {
      final type = row['type'] as String;
      final payload = jsonDecode(row['payload'] as String);
      bool success = false;

      try {
        if (type == 'page_view') {
          final res = await http.post(
            Uri.parse('${AppConstants.workerBaseUrl}/api/page-view'),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          );
          success = res.statusCode == 200 || res.statusCode == 429;
        } else if (type == 'exam_result') {
          final res = await http.post(
            Uri.parse('${AppConstants.workerBaseUrl}/api/exam/submit'),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          );
          success = res.statusCode == 200 || res.statusCode == 201;
        }
      } catch (_) {}

      if (success) {
        await database.delete('pending_sync',
            where: 'id=?', whereArgs: [row['id']]);
      }
    }
  }

  // ─── CACHE STATS ────────────────────────────────────────
  static Future<Map<String, dynamic>> getCacheStats() async {
    final database = await db;
    final pdfs = await database.query('cached_pdfs');
    final mcqs = await database.rawQuery('SELECT COUNT(*) as count FROM cached_mcqs');

    int totalSize = 0;
    for (final pdf in pdfs) {
      final path = pdf['local_path'] as String?;
      if (path != null) {
        try {
          totalSize += await File(path).length();
        } catch (_) {}
      }
    }

    return {
      'cached_pdfs': pdfs.length,
      'cached_mcqs': mcqs.first['count'] ?? 0,
      'total_size_mb': (totalSize / (1024 * 1024)).toStringAsFixed(1),
    };
  }

  static Future<void> clearAll() async {
    final pdfs = await getCachedPdfs();
    for (final pdf in pdfs) {
      final path = pdf['local_path'] as String?;
      if (path != null) {
        try { await File(path).delete(); } catch (_) {}
      }
    }
    final database = await db;
    await database.delete('cached_pdfs');
    await database.delete('cached_mcqs');
    await database.delete('cached_subjects');
    await database.delete('cached_chapters');
  }
}
