import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;

    // Inicializar base
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'timbre.db');

    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE eventos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT,
        estadoPuerta TEXT,
        deteccionMovimiento TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE fotos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT,
        ruta TEXT
      )
    ''');
  }

  // Insertar evento
  Future<int> insertarEvento(
    String estadoPuerta,
    String deteccionMovimiento,
  ) async {
    final db = await database;
    return await db.insert('eventos', {
      'timestamp': DateTime.now().toIso8601String(),
      'estadoPuerta': estadoPuerta,
      'deteccionMovimiento': deteccionMovimiento,
    });
  }

  // Insertar foto
  Future<int> insertarFoto(String ruta) async {
    final db = await database;
    return await db.insert('fotos', {
      'timestamp': DateTime.now().toIso8601String(),
      'ruta': ruta,
    });
  }

  // Opcional: obtener eventos
  Future<List<Map<String, dynamic>>> obtenerEventos() async {
    final db = await database;
    return await db.query('eventos', orderBy: 'timestamp DESC');
  }

  // Opcional: obtener fotos
  Future<List<Map<String, dynamic>>> obtenerFotos() async {
    final db = await database;
    return await db.query('fotos', orderBy: 'timestamp DESC');
  }
}
