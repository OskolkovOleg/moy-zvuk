import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/ui/theme.dart';
import 'package:zvuk_personal/ui/widgets.dart';
import 'package:zvuk_personal/ui/shuffle_sheet.dart';
import 'package:zvuk_personal/data/models.dart';

void main() {
  testWidgets('Equal-score range is disabled and usable with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
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
              title: 'Мои песни',
            ),
          ),
        ),
      ),
    );
    final slider = tester.widget<RangeSlider>(
      find.byKey(const Key('shuffle-score-slider')),
    );
    expect(slider.onChanged, isNull);
    expect(slider.values, const RangeValues(9, 9));
    expect(find.text('Подходит 1 трек'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('start-shuffle')))
          .onPressed,
      isNotNull,
    );
    expect(find.text('Все треки'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Both boundaries update counts and an empty selection disables playback',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: const Scaffold(
            body: ShuffleSheet(
              tracks: [
                Track(id: 'low', title: 'Low'),
                Track(id: 'middle', title: 'Middle'),
                Track(id: 'high', title: 'High'),
              ],
              ratings: {'low': Rating(-2, 11), 'high': Rating(18, 9)},
              title: 'Мои песни',
            ),
          ),
        ),
      );
      RangeSlider slider() => tester.widget<RangeSlider>(
        find.byKey(const Key('shuffle-score-slider')),
      );
      expect(slider().values, const RangeValues(-2, 18));
      slider().onChanged!(const RangeValues(-2, 9));
      await tester.pump();
      expect(find.text('Подходит 2 трека'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('shuffle-min'))).data,
        '-2',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('shuffle-max'))).data,
        '9',
      );
      slider().onChanged!(const RangeValues(10, 17));
      await tester.pump();
      expect(find.text('В этом диапазоне нет песен'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('start-shuffle')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
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
    expect(find.text('1'), findsOneWidget);
    expect(score, 1);
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byTooltip('Плюс один: Песня'));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
