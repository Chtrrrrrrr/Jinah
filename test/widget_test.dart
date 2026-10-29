import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jinah/app/app.dart';
import 'package:jinah/core/database/database.dart';
import 'package:jinah/core/settings/settings_controller.dart';
import 'package:jinah/features/todo/data/todo_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('应用启动并渲染 TODO 页面', (tester) async {
    // 宽屏表面：渲染 NavigationRail 布局
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final now = DateTime.now();
    final fake = TodoItem(
      id: '1',
      title: '完成 SPEC 设计文档',
      source: 'manual',
      status: 'open',
      confirmed: true,
      dueAt: DateTime(now.year, now.month, now.day, 23, 59),
      createdAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          todoListProvider.overrideWith((ref) => Stream.value([fake])),
        ],
        child: const JinahApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Jinah'), findsOneWidget);
    expect(find.text('完成 SPEC 设计文档'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
  });
}
