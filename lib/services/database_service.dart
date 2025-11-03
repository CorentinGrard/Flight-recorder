import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/flight_models.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('glider_tracker.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE flights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        duration INTEGER,
        max_altitude REAL,
        total_distance REAL,
        max_positive_g REAL,
        max_negative_g REAL,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sensor_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        flight_id INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        speed REAL,
        accel_x REAL,
        accel_y REAL,
        accel_z REAL,
        g_force REAL,
        heading REAL,
        FOREIGN KEY (flight_id) REFERENCES flights (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_flight_data ON sensor_data(flight_id, timestamp)
    ''');
  }

  // Flight operations
  Future<int> createFlight(Flight flight) async {
    final db = await database;
    return await db.insert('flights', flight.toMap());
  }

  Future<Flight?> getFlight(int id) async {
    final db = await database;
    final maps = await db.query(
      'flights',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Flight.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Flight>> getAllFlights() async {
    final db = await database;
    final maps = await db.query(
      'flights',
      orderBy: 'start_time DESC',
    );

    return maps.map((map) => Flight.fromMap(map)).toList();
  }

  Future<int> updateFlight(Flight flight) async {
    final db = await database;
    return await db.update(
      'flights',
      flight.toMap(),
      where: 'id = ?',
      whereArgs: [flight.id],
    );
  }

  Future<int> deleteFlight(int id) async {
    final db = await database;
    // This will also delete all sensor_data due to CASCADE
    return await db.delete(
      'flights',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Sensor data operations
  Future<int> insertSensorData(SensorDataPoint data) async {
    final db = await database;
    return await db.insert('sensor_data', data.toMap());
  }

  Future<void> insertSensorDataBatch(List<SensorDataPoint> dataPoints) async {
    final db = await database;
    final batch = db.batch();
    
    for (var point in dataPoints) {
      batch.insert('sensor_data', point.toMap());
    }
    
    await batch.commit(noResult: true);
  }

  Future<List<SensorDataPoint>> getSensorDataForFlight(int flightId) async {
    final db = await database;
    final maps = await db.query(
      'sensor_data',
      where: 'flight_id = ?',
      whereArgs: [flightId],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => SensorDataPoint.fromMap(map)).toList();
  }

  Future<int> getSensorDataCount(int flightId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sensor_data WHERE flight_id = ?',
      [flightId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Calculate flight statistics
  Future<Flight> calculateFlightStats(int flightId) async {
    final flight = await getFlight(flightId);
    if (flight == null) throw Exception('Flight not found');

    final dataPoints = await getSensorDataForFlight(flightId);
    if (dataPoints.isEmpty) return flight;

    // Calculate max altitude
    double? maxAltitude = dataPoints
        .where((p) => p.altitude != null)
        .map((p) => p.altitude!)
        .fold(null, (max, alt) => max == null || alt > max ? alt : max);

    // Calculate total distance
    double totalDistance = 0;
    for (int i = 1; i < dataPoints.length; i++) {
      totalDistance += dataPoints[i - 1].distanceTo(dataPoints[i]);
    }

    // Calculate max G forces
    double? maxPositiveG;
    double? maxNegativeG;
    
    for (var point in dataPoints) {
      if (point.gForce != null) {
        if (maxPositiveG == null || point.gForce! > maxPositiveG) {
          maxPositiveG = point.gForce;
        }
        if (maxNegativeG == null || point.gForce! < maxNegativeG) {
          maxNegativeG = point.gForce;
        }
      }
    }

    // Calculate duration
    int? duration;
    if (flight.endTime != null) {
      duration = flight.endTime!.difference(flight.startTime).inSeconds;
    }

    return flight.copyWith(
      duration: duration,
      maxAltitude: maxAltitude,
      totalDistance: totalDistance,
      maxPositiveG: maxPositiveG,
      maxNegativeG: maxNegativeG,
    );
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
