import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jinah/app/theme.dart';

void main() {
  test('Obsidian 深色 token 与设计规范一致', () {
    const p = ObsidianPalette.dark;
    expect(p.bgPrimary, const Color(0xFF1E1E1E));
    expect(p.bgSecondary, const Color(0xFF262626));
    expect(p.border, const Color(0xFF363636));
    expect(p.textNormal, const Color(0xFFDCDDDE));
    expect(p.textMuted, const Color(0xFF999999));
  });

  test('Obsidian 浅色 token 与设计规范一致', () {
    const p = ObsidianPalette.light;
    expect(p.bgPrimary, const Color(0xFFFFFFFF));
    expect(p.bgSecondary, const Color(0xFFF2F3F5));
    expect(p.border, const Color(0xFFE1E4E8));
    expect(p.textNormal, const Color(0xFF222222));
  });

  test('主题使用 Obsidian 背景与强调色', () {
    final theme = buildJinahTheme(
      p: ObsidianPalette.dark,
      accent: kDefaultAccent,
      brightness: Brightness.dark,
    );
    expect(theme.scaffoldBackgroundColor, const Color(0xFF1E1E1E));
    expect(theme.colorScheme.primary, kDefaultAccent);
    expect(theme.brightness, Brightness.dark);
  });
}
