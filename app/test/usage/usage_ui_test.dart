// Where the person is told and can say no: 设置 › 隐私与分享 › 改进 DSH Go.
// Fork (a802522): first run's welcome page used to carry the same switch over
// 「开始」; the row was removed entirely, so the welcome-row tests below are
// gone too. The welcome golden still exists and must be regenerated
// (flutter test --update-goldens) because the page no longer shows the row.
// Seeing the settings switch only records that the person was told.
//
//   flutter test --update-goldens test/usage/usage_ui_test.dart

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/android_features.dart';
import 'package:dsh_app/ui/onboarding/welcome_page.dart';
import 'package:dsh_app/ui/settings/usage_stats_section.dart';
import 'package:dsh_app/ui/settings/privacy_page.dart';
import 'package:dsh_app/usage/usage_stats.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine_settings/support.dart' as engine;
import '../shell/golden_harness.dart';
import '../support/english_preview.dart';

Future<void> _pumpWelcome(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool english = false,
  Brightness brightness = Brightness.light,
}) async {
  if (english) useEnglish();
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  tester.view.padding = const FakeViewPadding(top: 32 * 2, bottom: 24 * 2);
  tester.view.viewPadding = const FakeViewPadding(top: 32 * 2, bottom: 24 * 2);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final page = WelcomePage(onStart: () {});
  await tester.pumpWidget(goldenApp(home: english ? inEnglish(page) : page, brightness: brightness));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

Future<Map<String, Object?>> _stored() async {
  final prefs = await SharedPreferences.getInstance();
  return {for (final k in prefs.getKeys()) k: prefs.get(k)};
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('welcome, in English (light)', (tester) async {
    await tester.runAsync(loadGoldenFonts);
    await _pumpWelcome(tester, english: true);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/en_welcome_light.png'));
  });


  group('设置 › 隐私与分享', () {
    Future<void> pumpPrivacy(WidgetTester tester) => engine.pumpPage(
      tester,
      const PrivacyPage(),
      overrides: engine.engineOverrides(DshClient.withCarrier(engine.FakeSettingsHost())),
    );

    testWidgets('the page counts as being told; the switch turns it all off', (tester) async {
      await pumpPrivacy(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      final container = ProviderScope.containerOf(tester.element(find.byType(PrivacyPage)));
      expect(container.read(usageStatsProvider).noticed, isTrue);
      final tile = find.widgetWithText(InkWell, appL10n.usageStatsTitle);
      expect(tester.widget<Switch>(find.descendant(of: tile, matching: find.byType(Switch))).value, isTrue);
      expect(find.text(appL10n.usageStatsFooter), findsOneWidget);

      await tester.tap(tile);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(container.read(usageStatsProvider).enabled, isFalse);
      expect(tester.widget<Switch>(find.descendant(of: tile, matching: find.byType(Switch))).value, isFalse);
      final stored = (await tester.runAsync(_stored))!;
      expect(stored[UsageStatsController.enabledKey], isFalse);
      for (final key in [UsageStatsController.iidKey, UsageStatsController.daysKey]) {
        expect(stored.containsKey(key), isFalse, reason: key);
      }
    });

    testWidgets('a cold start shows it off once it was turned off', (tester) async {
      SharedPreferences.setMockInitialValues({
        UsageStatsController.enabledKey: false,
        UsageStatsController.noticedKey: true,
      });
      await pumpPrivacy(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      final tile = find.widgetWithText(InkWell, appL10n.usageStatsTitle);
      expect(tester.widget<Switch>(find.descendant(of: tile, matching: find.byType(Switch))).value, isFalse);
    });
  });

  group('on HarmonyOS, where nothing is sent yet', () {
    final zh = lookupL10n(AppLocale.zhCN);
    Future<void> pump(WidgetTester tester, Widget home, String os) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        goldenApp(
          home: home,
          brightness: Brightness.light,
          overrides: [
            ...engine.engineOverrides(DshClient.withCarrier(engine.FakeSettingsHost())),
            operatingSystemProvider.overrideWithValue(os),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Widget section() => const Scaffold(body: SingleChildScrollView(child: UsageStatsSection()));

    testWidgets('settings says so, with the switch off and locked', (tester) async {
      await pump(tester, section(), 'ohos');
      expect(find.text(zh.harmonyUsageNotSent), findsOneWidget);
      expect(find.text(zh.usageStatsFooter), findsNothing);
      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isFalse);
      expect(toggle.onChanged, isNull);
    });

    testWidgets('on Android: as ever', (tester) async {
      await pump(tester, section(), 'android');
      expect(find.text(zh.usageStatsAndroidFooter), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    });


  });
}
