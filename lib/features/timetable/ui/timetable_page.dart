import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../data/timetable_repository.dart';
import '../domain/term_calendar.dart';
import '../domain/week_pattern.dart';
import '../export/ics_export.dart';
import '../import/open_platform_import.dart';
import '../import/webview_capture_page.dart';

/// Obsidian 风格的课程配色（低饱和、可区分）。
const _coursePalette = [
  Color(0xFF7F6DF2),
  Color(0xFFE8590C),
  Color(0xFF2F9E44),
  Color(0xFF1971C2),
  Color(0xFFE64980),
  Color(0xFFF08C00),
  Color(0xFF0CA678),
  Color(0xFF6741D9),
];

Color courseColor(Course course) {
  if (course.colorValue != null) return Color(course.colorValue!);
  return _coursePalette[course.id.hashCode.abs() % _coursePalette.length];
}

/// 课表主页面：周切换 + 网格渲染（Obsidian callout 式课程块）。
class TimetablePage extends ConsumerWidget {
  const TimetablePage({super.key});

  static const _cellHeight = 52.0;
  static const _colWidth = 128.0;
  static const _periodCount = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final termAsync = ref.watch(currentTermProvider);
    final entriesAsync = ref.watch(weekEntriesProvider);
    final coursesAsync = ref.watch(coursesMapProvider);
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final accent = Theme.of(context).colorScheme.primary;

    final term = termAsync.value;
    final selected = ref.watch(selectedWeekProvider);

    final now = DateTime.now();
    final calendar = term == null
        ? null
        : TermCalendar(
            calendarId: term.id,
            name: term.name,
            year: term.year,
            term: term.termIndex,
            firstWeekStart: term.firstWeekStart,
            endDate: term.endDate,
            totalWeeks: term.totalWeeks,
            isCurrent: term.isCurrent,
          );
    final week = selected ?? calendar?.weekOf(now) ?? 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: term == null || calendar == null
          ? _ImportHint(muted: muted)
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // 头部：标题 + 周切换
                Row(
                  children: [
                    Text('课表', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(width: 16),
                    IconButton(
                      tooltip: '上一周',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: week > 1
                          ? () => ref
                              .read(selectedWeekProvider.notifier)
                              .set(week - 1)
                          : null,
                    ),
                    Text(
                      '第$week周 · ${calendar.weekLabel(week)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      tooltip: '下一周',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: week < term.totalWeeks
                          ? () => ref
                              .read(selectedWeekProvider.notifier)
                              .set(week + 1)
                          : null,
                    ),
                    if (selected != null)
                      TextButton(
                        onPressed: () => ref
                            .read(selectedWeekProvider.notifier)
                            .set(null),
                        child: const Text('回到本周'),
                      ),
                    IconButton(
                      tooltip: '导出 ICS（导入系统日历）',
                      icon: const Icon(Icons.download_outlined, size: 18),
                      onPressed: () => _exportIcs(context, ref, term),
                    ),
                    const Spacer(),
                    Text(term.name, style: TextStyle(color: muted, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                entriesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('加载失败：$e'),
                  data: (entries) {
                    final courses = coursesAsync.value ?? const {};
                    final showWeekend =
                        entries.any((e) => e.weekday >= 6);
                    final days = weekdayColumns(
                      showWeekend: showWeekend,
                      startOnToday: false,
                      today: now,
                    );
                    final todayIdx = todayColumn(
                      term: calendar,
                      week: week,
                      days: days,
                      today: now,
                    );
                    return _buildGrid(
                      context,
                      entries: entries,
                      courses: courses,
                      days: days,
                      todayIdx: todayIdx,
                      muted: muted,
                      accent: accent,
                    );
                  },
                ),
              ],
            ),
    );
  }

  Future<void> _exportIcs(BuildContext context, WidgetRef ref, Term term) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final entries = await ref
          .read(timetableRepositoryProvider)
          .watchEntries(term.id)
          .first;
      final courses = ref.read(coursesMapProvider).value ?? const <String, Course>{};
      final ics = buildTimetableIcs(
        term: TermCalendar(
          calendarId: term.id,
          name: term.name,
          year: term.year,
          term: term.termIndex,
          firstWeekStart: term.firstWeekStart,
          endDate: term.endDate,
          totalWeeks: term.totalWeeks,
          isCurrent: term.isCurrent,
        ),
        courses: courses,
        entries: entries,
      );
      final location = await getSaveLocation(
        suggestedName: 'jinah-timetable.ics',
      );
      if (location == null || !context.mounted) return;
      await File(location.path).writeAsString(ics);
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('ICS 已导出，可导入系统日历')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    }
  }

  Widget _buildGrid(
    BuildContext context, {
    required List<ScheduleEntry> entries,
    required Map<String, Course> courses,
    required List<int> days,
    required int todayIdx,
    required Color? muted,
    required Color accent,
  }) {
    final border = Theme.of(context).dividerColor;

    final byWeekday = <int, List<ScheduleEntry>>{};
    for (final e in entries) {
      byWeekday.putIfAbsent(e.weekday, () => []).add(e);
    }
    for (final list in byWeekday.values) {
      list.sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
    }

    const dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 48 + days.length * _colWidth,
        child: Column(
          children: [
            // 表头
            Row(
              children: [
                const SizedBox(width: 48),
                for (var i = 0; i < days.length; i++)
                  Container(
                    width: _colWidth,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: accent, width: 2),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '周${dayLabels[days[i] - 1]}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              i == todayIdx ? FontWeight.w700 : FontWeight.w400,
                          color: i == todayIdx ? accent : muted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // 节次网格
            SizedBox(
              height: _cellHeight * _periodCount,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 48,
                    child: Column(
                      children: [
                        for (var p = 1; p <= _periodCount; p++)
                          SizedBox(
                            height: _cellHeight,
                            child: Center(
                              child: Text(
                                '$p',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var i = 0; i < days.length; i++)
                    Container(
                      width: _colWidth,
                      height: _cellHeight * _periodCount,
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: border, width: 0.5),
                        ),
                        color: i == todayIdx
                            ? accent.withValues(alpha: 0.05)
                            : null,
                      ),
                      child: Stack(
                        children: [
                          for (final e in byWeekday[days[i]] ?? const <ScheduleEntry>[])
                            Positioned(
                              top: (e.startPeriod - 1) * _cellHeight + 2,
                              left: 3,
                              right: 3,
                              height:
                                  (e.endPeriod - e.startPeriod + 1) * _cellHeight - 4,
                              child: _CourseBlock(
                                entry: e,
                                course: courses[e.courseId],
                                muted: muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Obsidian callout 式课程块：左边条 + 低饱和底色。
class _CourseBlock extends StatelessWidget {
  const _CourseBlock({required this.entry, required this.course, this.muted});

  final ScheduleEntry entry;
  final Course? course;
  final Color? muted;

  @override
  Widget build(BuildContext context) {
    final color = course == null ? Colors.grey : courseColor(course!);
    final weeks = WeekPattern.fromBits(entry.weekBits);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            course?.name ?? '未绑定课程',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, height: 1.2),
          ),
          const Spacer(),
          if (entry.location != null && entry.location!.isNotEmpty)
            Text(
              entry.location!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: muted),
            ),
          if (weeks.parityLabel == null && weeks.isNotEmpty)
            Text(
              weeks.display(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: muted),
            )
          else if (weeks.parityLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                weeks.parityLabel!,
                style: TextStyle(fontSize: 9, color: color),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImportHint extends ConsumerWidget {
  const _ImportHint({required this.muted});

  final Color? muted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_view_week, size: 48, color: muted),
          const SizedBox(height: 12),
          Text('还没有课表', style: TextStyle(color: muted)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              final imported = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => const WebViewCapturePage(),
                ),
              );
              if (imported == true && context.mounted) {
                ref.read(selectedWeekProvider.notifier).set(null);
              }
            },
            icon: const Icon(Icons.login, size: 16),
            label: const Text('从 1系统 导入'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await runOpenPlatformImportFlow(context, ref);
              ref.read(selectedWeekProvider.notifier).set(null);
            },
            icon: const Icon(Icons.api, size: 16),
            label: const Text('开放平台导入（需 Client ID）'),
          ),
          const SizedBox(height: 8),
          Text(
            '截图识别导入：收件箱 → 导入截图',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
