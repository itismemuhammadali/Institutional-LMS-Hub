import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../models/calendar_event.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;
  static List<CalendarEvent> _inMemoryEvents = [];

  Future<Database> get database async {
    if (kIsWeb) {
      // For web, we'll use in-memory storage
      throw UnsupportedError('Database not supported on web platform');
    }
    
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'calendar_events.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE calendar_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        eventName TEXT NOT NULL,
        duration TEXT NOT NULL,
        createdAt TEXT,
        updatedAt TEXT
      )
    ''');

    // Create index for date queries
    await db.execute('CREATE INDEX idx_date ON calendar_events(date)');
    
    // Insert demo events for the current year
    await _insertDemoEvents(db);
  }

  Future<void> _insertDemoEvents(Database db) async {
    final now = DateTime.now();
    final currentYear = now.year;
    
    final demoEvents = [
      CalendarEvent(
        date: DateTime(currentYear, 8, 4),
        eventName: 'Team Meeting',
        duration: '1 hour',
        createdAt: now,
        updatedAt: now,
      ),
      CalendarEvent(
        date: DateTime(currentYear, 8, 5),
        eventName: 'Project Deadline',
        duration: '2 hours',
        createdAt: now,
        updatedAt: now,
      ),
      CalendarEvent(
        date: DateTime(currentYear, 8, 10),
        eventName: 'Exam',
        duration: '3 hours',
        createdAt: now,
        updatedAt: now,
      ),
      CalendarEvent(
        date: DateTime(currentYear, 8, 15),
        eventName: 'Client Call',
        duration: '45 minutes',
        createdAt: now,
        updatedAt: now,
      ),
      CalendarEvent(
        date: DateTime(currentYear, 8, 16),
        eventName: 'Meeting',
        duration: '1 hour',
        createdAt: now,
        updatedAt: now,
      ),
      CalendarEvent(
        date: DateTime(currentYear, 8, 18),
        eventName: 'Code Review',
        duration: '1.5 hours',
        createdAt: now,
        updatedAt: now,
      ),
      CalendarEvent(
        date: DateTime(currentYear, 8, 19),
        eventName: 'Project',
        duration: '4 hours',
        createdAt: now,
        updatedAt: now,
      ),
      CalendarEvent(
        date: DateTime(currentYear, 8, 22),
        eventName: 'Presentation',
        duration: '2 hours',
        createdAt: now,
        updatedAt: now,
      ),
      CalendarEvent(
        date: DateTime(currentYear, 8, 25),
        eventName: 'Workshop',
        duration: '3 hours',
        createdAt: now,
        updatedAt: now,
      ),
      CalendarEvent(
        date: DateTime(currentYear, 8, 27),
        eventName: 'Deadline',
        duration: '1 hour',
        createdAt: now,
        updatedAt: now,
      ),
      CalendarEvent(
        date: DateTime(currentYear, 8, 28),
        eventName: 'Final Review',
        duration: '2 hours',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    for (var event in demoEvents) {
      await db.insert('calendar_events', event.toMap());
    }
  }

  Future<int> insertEvent(CalendarEvent event) async {
    if (kIsWeb) {
      // For web, use in-memory storage
      final now = DateTime.now();
      final eventWithTimestamps = event.copyWith(
        id: _inMemoryEvents.length + 1,
        createdAt: now,
        updatedAt: now,
      );
      _inMemoryEvents.add(eventWithTimestamps);
      return eventWithTimestamps.id!;
    }
    
    final db = await database;
    final now = DateTime.now();
    final eventWithTimestamps = event.copyWith(
      createdAt: now,
      updatedAt: now,
    );
    return await db.insert('calendar_events', eventWithTimestamps.toMap());
  }

  Future<List<CalendarEvent>> getEventsForMonth(DateTime month) async {
    if (kIsWeb) {
      // For web, return empty list to avoid errors
      return [];
    }
    
    try {
      final db = await database;
      final startDate = DateTime(month.year, month.month, 1);
      final endDate = DateTime(month.year, month.month + 1, 0);
      
      final List<Map<String, dynamic>> maps = await db.query(
        'calendar_events',
        where: 'date BETWEEN ? AND ?',
        whereArgs: [startDate.toIso8601String(), endDate.toIso8601String()],
        orderBy: 'date ASC',
      );

      return List.generate(maps.length, (i) {
        return CalendarEvent.fromMap(maps[i]);
      });
    } catch (e) {
      // Return empty list if database is not available
      return [];
    }
  }

  Future<List<CalendarEvent>> getEventsForDate(DateTime date) async {
    if (kIsWeb) {
      // For web, filter in-memory events
      return _inMemoryEvents.where((event) {
        return event.date.year == date.year &&
               event.date.month == date.month &&
               event.date.day == date.day;
      }).toList();
    }
    
    final db = await database;
    final dateStr = DateTime(date.year, date.month, date.day).toIso8601String();
    
    final List<Map<String, dynamic>> maps = await db.query(
      'calendar_events',
      where: 'date LIKE ?',
      whereArgs: ['$dateStr%'],
      orderBy: 'date ASC',
    );

    return List.generate(maps.length, (i) {
      return CalendarEvent.fromMap(maps[i]);
    });
  }

  Future<int> updateEvent(CalendarEvent event) async {
    if (kIsWeb) {
      // For web, update in-memory event
      final index = _inMemoryEvents.indexWhere((e) => e.id == event.id);
      if (index != -1) {
        final now = DateTime.now();
        final eventWithTimestamp = event.copyWith(updatedAt: now);
        _inMemoryEvents[index] = eventWithTimestamp;
        return 1;
      }
      return 0;
    }
    
    final db = await database;
    final now = DateTime.now();
    final eventWithTimestamp = event.copyWith(updatedAt: now);
    
    return await db.update(
      'calendar_events',
      eventWithTimestamp.toMap(),
      where: 'id = ?',
      whereArgs: [event.id],
    );
  }

  Future<int> deleteEvent(int id) async {
    if (kIsWeb) {
      // For web, remove from in-memory events
      final initialLength = _inMemoryEvents.length;
      _inMemoryEvents.removeWhere((event) => event.id == id);
      return initialLength - _inMemoryEvents.length;
    }
    
    final db = await database;
    return await db.delete(
      'calendar_events',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    if (!kIsWeb) {
      final db = await database;
      await db.close();
    }
  }

  // Initialize demo events for web
  void initializeWebEvents() {
    if (kIsWeb && _inMemoryEvents.isEmpty) {
      final now = DateTime.now();
      final currentYear = now.year;
      
      _inMemoryEvents = [
        CalendarEvent(
          id: 1,
          date: DateTime(currentYear, 8, 4),
          eventName: 'Team Meeting',
          duration: '1 hour',
          createdAt: now,
          updatedAt: now,
        ),
        CalendarEvent(
          id: 2,
          date: DateTime(currentYear, 8, 5),
          eventName: 'Project Deadline',
          duration: '2 hours',
          createdAt: now,
          updatedAt: now,
        ),
        CalendarEvent(
          id: 3,
          date: DateTime(currentYear, 8, 10),
          eventName: 'Exam',
          duration: '3 hours',
          createdAt: now,
          updatedAt: now,
        ),
        CalendarEvent(
          id: 4,
          date: DateTime(currentYear, 8, 15),
          eventName: 'Client Call',
          duration: '45 minutes',
          createdAt: now,
          updatedAt: now,
        ),
        CalendarEvent(
          id: 5,
          date: DateTime(currentYear, 8, 16),
          eventName: 'Meeting',
          duration: '1 hour',
          createdAt: now,
          updatedAt: now,
        ),
        CalendarEvent(
          id: 6,
          date: DateTime(currentYear, 8, 18),
          eventName: 'Code Review',
          duration: '1.5 hours',
          createdAt: now,
          updatedAt: now,
        ),
        CalendarEvent(
          id: 7,
          date: DateTime(currentYear, 8, 19),
          eventName: 'Project',
          duration: '4 hours',
          createdAt: now,
          updatedAt: now,
        ),
        CalendarEvent(
          id: 8,
          date: DateTime(currentYear, 8, 22),
          eventName: 'Presentation',
          duration: '2 hours',
          createdAt: now,
          updatedAt: now,
        ),
        CalendarEvent(
          id: 9,
          date: DateTime(currentYear, 8, 25),
          eventName: 'Workshop',
          duration: '3 hours',
          createdAt: now,
          updatedAt: now,
        ),
        CalendarEvent(
          id: 10,
          date: DateTime(currentYear, 8, 27),
          eventName: 'Deadline',
          duration: '1 hour',
          createdAt: now,
          updatedAt: now,
        ),
        CalendarEvent(
          id: 11,
          date: DateTime(currentYear, 8, 28),
          eventName: 'Final Review',
          duration: '2 hours',
          createdAt: now,
          updatedAt: now,
        ),
      ];
    }
  }
}
