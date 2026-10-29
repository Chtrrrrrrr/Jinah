import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// 课程。Canvas/1系统导入的课程与本地手动创建的课程共用一张表，
/// source/sourceRef 记录来源，sourceRef 用于去重。
class Courses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get code => text().nullable()();
  TextColumn get teacher => text().nullable()();
  IntColumn get colorValue => integer().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get sourceRef => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 作业/任务条目。status: open | done | dismissed。
class TodoItems extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get courseId => text().nullable().references(Courses, #id)();
  TextColumn get source =>
      text().withDefault(const Constant('manual'))(); // canvas|notice|manual|screenshot
  TextColumn get sourceRef => text().nullable()();
  TextColumn get detail => text().nullable()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  BoolColumn get confirmed => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 学期（教学周日历）。
class Terms extends Table {
  TextColumn get id => text()(); // calendarId
  TextColumn get name => text()();
  IntColumn get year => integer()();
  IntColumn get termIndex => integer()(); // 1秋 2春 3暑
  DateTimeColumn get firstWeekStart => dateTime()(); // 第1周周一
  DateTimeColumn get endDate => dateTime()();
  IntColumn get totalWeeks => integer()();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 课表条目（一次课）。周信息存位掩码 + 可再解析文本。
class ScheduleEntries extends Table {
  TextColumn get id => text()();
  TextColumn get termId => text().references(Terms, #id)();
  TextColumn get courseId => text().references(Courses, #id)();
  IntColumn get weekday => integer()(); // DateTime.monday=1 .. sunday=7
  IntColumn get startPeriod => integer()();
  IntColumn get endPeriod => integer()();
  IntColumn get weekBits => integer()(); // WeekPattern 位掩码
  TextColumn get weekCanonical =>
      text().withDefault(const Constant(''))(); // "1,3,5"，可再解析
  TextColumn get rawWeekText => text().withDefault(const Constant(''))();
  TextColumn get location => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get sourceRef => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Courses, TodoItems, Terms, ScheduleEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'jinah'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(terms);
            await m.createTable(scheduleEntries);
          }
        },
      );
}
