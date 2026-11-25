import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/score_distribution.dart';

class ScoreDistributionChart extends StatelessWidget {
  const ScoreDistributionChart({
    super.key,
    required this.bands,
    required this.selected,
    required this.distribution,
    required this.onSelect,
  });
  final List<ScoreBand> bands;
  final ScoreBand selected;
  final ScoreDistribution distribution;
  final ValueChanged<ScoreBand> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxCount = bands.map((b) => b.count).reduce(math.max);
    final axisMax = maxCount.isOdd ? maxCount + 1 : maxCount;
    final scale = MediaQuery.textScalerOf(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return LayoutBuilder(
      builder: (context, constraints) {
        final digits = axisMax.toString().length;
        final axisWidth = math.max(24.0, scale.scale(11) * digits * .65 + 8);
        final plotWidth = constraints.maxWidth - axisWidth;
        final slotWidth = plotWidth / bands.length;
        final longest = bands.map((b) => b.axisLabel.length).reduce(math.max);
        final showAll = slotWidth >= scale.scale(11) * longest * .7 + 6;
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: axisWidth,
                  height: 190,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$axisMax',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${axisMax ~/ 2}',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '0',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 190,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  for (var i = 0; i < 3; i++)
                                    Divider(
                                      height: 1,
                                      color: scheme.outlineVariant.withValues(
                                        alpha: .5,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final band in bands)
                                  Expanded(
                                    child: Semantics(
                                      button: true,
                                      selected: band.low == selected.low,
                                      label:
                                          '${band.label}, ${songCountLabel(band.count)}, ${distribution.shareLabel(band.count)}',
                                      child: Tooltip(
                                        excludeFromSemantics: true,
                                        message:
                                            '${band.label} · ${songCountLabel(band.count)}',
                                        child: InkWell(
                                          key: ValueKey(
                                            'score-band-${band.low}-${band.high}',
                                          ),
                                          onTap: () => onSelect(band),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: math.min(
                                                4,
                                                slotWidth * .13,
                                              ),
                                            ),
                                            child: Align(
                                              alignment: Alignment.bottomCenter,
                                              child: AnimatedContainer(
                                                duration: duration,
                                                curve: Curves.easeOutCubic,
                                                width: math.min(
                                                  44.0,
                                                  slotWidth,
                                                ),
                                                height:
                                                    band.count / axisMax * 190,
                                                decoration: BoxDecoration(
                                                  color:
                                                      band.low == selected.low
                                                      ? scheme.primary
                                                      : scheme.secondary
                                                            .withValues(
                                                              alpha: .65,
                                                            ),
                                                  borderRadius:
                                                      const BorderRadius.vertical(
                                                        top: Radius.circular(7),
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (showAll)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              for (final band in bands)
                                Expanded(
                                  child: Text(
                                    band.axisLabel,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: band.low == selected.low
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
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
            Padding(
              padding: EdgeInsets.only(top: showAll ? 8 : 12, left: axisWidth),
              child: showAll
                  ? Text(
                      'Баллы',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          Text(
                            'От ${displayScore(bands.first.low)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            'До ${displayScore(bands.last.high)} баллов',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
