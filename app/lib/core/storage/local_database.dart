import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  static Database? _db;

  static Future<Database> get instance async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'finance_control.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, _) => _createTables(db),
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          // v1→v2: adiciona colunas de categoria e recria índice
          await db.execute(
            'ALTER TABLE transacao_cache ADD COLUMN categoria_id INTEGER',
          );
          await db.execute(
            'ALTER TABLE transacao_cache ADD COLUMN categoria_nome TEXT',
          );
        }
        if (oldVersion < 3) await _criarResumoCache(db);
      },
    );
  }

  /// Guarda a última resposta de consultas consolidadas (ex.: saldo), em JSON.
  static Future<void> _criarResumoCache(Database db) => db.execute('''
      CREATE TABLE resumo_cache (
        chave       TEXT PRIMARY KEY,
        conteudo    TEXT NOT NULL,
        atualizado  TEXT NOT NULL
      )
    ''');

  static Future<void> salvarSaldo(Map<String, dynamic> saldo) async {
    final db = await instance;
    await db.insert(
      'resumo_cache',
      {
        'chave': 'saldo',
        'conteudo': jsonEncode(saldo),
        'atualizado': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, dynamic>?> buscarSaldo() async {
    final db = await instance;
    final rows = await db.query('resumo_cache', where: 'chave = ?', whereArgs: ['saldo'], limit: 1);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['conteudo'] as String) as Map<String, dynamic>;
  }

  static Future<void> _createTables(Database db) async {
    await _criarResumoCache(db);

    await db.execute('''
      CREATE TABLE saldo_cache (
        conta_id    INTEGER PRIMARY KEY,
        saldo       REAL    NOT NULL,
        moeda       TEXT    NOT NULL DEFAULT 'BRL',
        atualizado  TEXT    NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE transacao_cache (
        id            TEXT    PRIMARY KEY,
        conta_id      INTEGER NOT NULL,
        descricao     TEXT    NOT NULL,
        valor         REAL    NOT NULL,
        tipo          TEXT    NOT NULL,
        data          TEXT    NOT NULL,
        categoria_id  INTEGER,
        categoria_nome TEXT,
        atualizado    TEXT    NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_transacao_conta ON transacao_cache (conta_id, data DESC)',
    );
  }

  static Future<void> salvarTransacoes(List<dynamic> transacoes) async {
    final db = await instance;
    final batch = db.batch();
    for (final tx in transacoes) {
      final t = tx as Map<String, dynamic>;
      final cat = t['categoria'] as Map<String, dynamic>?;
      batch.insert(
        'transacao_cache',
        {
          'id': (t['idExternoPluggy'] as String?) ?? t['id'].toString(),
          'conta_id': t['contaId'] as int? ?? 0,
          'descricao': t['descricao'] as String? ?? '',
          'valor': double.tryParse(t['valor']?.toString() ?? '0') ?? 0.0,
          'tipo': t['tipo'] as String? ?? '',
          'data': t['data'] as String? ?? '',
          'categoria_id': t['categoriaId'] as int?,
          'categoria_nome': cat?['nome'] as String?,
          'atualizado': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> buscarTransacoesCache({
    int page = 1,
    int limit = 20,
    int? categoriaId,
    String? tipo,
    String? de,
    String? ate,
  }) async {
    final db = await instance;
    final where = StringBuffer('1=1');
    final args = <dynamic>[];

    if (categoriaId != null) {
      where.write(' AND categoria_id = ?');
      args.add(categoriaId);
    }
    if (tipo != null) {
      where.write(' AND tipo = ?');
      args.add(tipo);
    }
    if (de != null) {
      where.write(' AND data >= ?');
      args.add(de);
    }
    if (ate != null) {
      where.write(' AND data <= ?');
      args.add(ate);
    }

    return db.query(
      'transacao_cache',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'data DESC',
      limit: limit,
      offset: (page - 1) * limit,
    );
  }

  /// Remove todo o cache local — chamado no logout e revogação de consentimento.
  static Future<void> limpar() async {
    final db = await instance;
    await db.delete('saldo_cache');
    await db.delete('resumo_cache');
    await db.delete('transacao_cache');
    debugPrint('[LocalDatabase] Cache limpo');
  }
}
