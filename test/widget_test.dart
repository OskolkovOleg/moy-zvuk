import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/ui/theme.dart';
import 'package:zvuk_personal/ui/widgets.dart';
import 'package:zvuk_personal/ui/shuffle_sheet.dart';
import 'package:zvuk_personal/data/models.dart';

void main() {
  testWidgets('Best-track slider works with one track and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: const Scaffold(
            body: ShuffleSheet(
              tracks: [Track(id: 'one', title: 'Песня')],
              ratings: {},
              title: 'Плейлист',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Лучшие по баллам'));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(
      find.byKey(const Key('shuffle-count-slider')),
    );
    expect(slider.onChanged, isNull);
    expect(
      tester.widget<Text>(find.byKey(const Key('shuffle-count'))).data,
      '1',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Order arrows have accessible targets and disable list boundaries',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var movement = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Center(
              child: OrderControls(
                title: 'Песня',
                onUp: null,
                onDown: () => movement++,
              ),
            ),
          ),
        ),
      );
      final up = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == 'Выше: Песня',
        ),
      );
      expect(up.onPressed, isNull);
      await tester.tap(find.byTooltip('Ниже: Песня'));
      expect(movement, 1);
      final size = tester.getSize(find.byTooltip('Ниже: Песня'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    },
  );
  testWidgets('Rating buttons accumulate at 360px and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var score = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Center(
                child: RatingControls(
                  score: score,
                  title: 'Песня',
                  onVote: (delta) => setState(() => score += delta),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Плюс один: Песня'));
    await tester.pump();
    await tester.tap(find.byTooltip('Плюс один: Песня'));
    await tester.pump();
    await tester.tap(find.byTooltip('Минус один: Песня'));
    await tester.pump();
    expect(find.text('+1'), findsOneWidget);
    expect(score, 1);
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byTooltip('Плюс один: Песня'));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
