import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/score_distribution.dart';
import 'catalog_widgets.dart';
import 'score_distribution_chart.dart';
import 'widgets.dart';

class ScoreDistributionScreen extends StatefulWidget {
  const ScoreDistributionScreen(this.app, {super.key});
  final AppController app;
  @override
  State<ScoreDistributionScreen> createState() =>
      _ScoreDistributionScreenState();
}

class _ScoreDistributionScreenState extends State<ScoreDistributionScreen> {
  late final String? owner;
  @override
  void initState() {
    super.initState();
    owner = widget.app.account?.id;
  }

  int? selectedScore;

  Future<void> chooseBand(ScoreBand selected) async {
    final choice = await showModalBottomSheet<ScoreBand>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => AnimatedBuilder(
        animation: widget.app,
        builder: (context, _) {
          final sameAccount = widget.app.account?.id == owner;
          final bands = ScoreDistribution.fromTracks(
            sameAccount ? widget.app.favoriteTracks : const [],
            widget.app.ratings,
          ).bands();
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(
                      sameAccount ? 'Выбрать балл' : 'Аккаунт изменился',
                    ),
                  ),
                  for (final band in bands)
                    ListTile(
                      title: Text(band.label),
                      subtitle: Text(songCountLabel(band.count)),
                      trailing: band.contains(selectedScore ?? selected.low)
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.pop(sheet, band),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted && choice != null && widget.app.account?.id == owner) {
      setState(() => selectedScore = choice.low);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final app = widget.app, scheme = Theme.of(context).colorScheme;
      final accountChanged = owner == null || app.account?.id != owner;
      final distribution = ScoreDistribution.fromTracks(
        accountChanged ? const [] : app.favoriteTracks,
        app.ratings,
      );
      final bands = distribution.bands();
      final selected = bands.isEmpty
          ? null
          : bands
                    .where(
                      (b) =>
                          selectedScore != null && b.contains(selectedScore!),
                    )
                    .firstOrNull ??
                bands.reduce((a, b) => a.count >= b.count ? a : b);
      return PlayerScaffold(
        app,
        title: 'Баллы',
        body: ListView(
          key: const Key('score-distribution-list'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              'Музыка\nв баллах',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Вся библиотека «Мои песни»',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            if (selected == null)
              EmptyState(
                icon: Icons.bar_chart_rounded,
                title: accountChanged ? 'Аккаунт изменился' : 'Пока нет песен',
                message: accountChanged
                    ? 'Открой статистику снова из настроек.'
                    : 'Добавь песни в библиотеку — здесь появится распределение по баллам.',
              )
            else ...[
              Text(
                songCountLabel(distribution.total),
                key: const Key('distribution-total'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const Key('distribution-choose-score'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(48, 48),
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: () => chooseBand(selected),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          children: [
                            Text(
                              selected.label,
                              key: const Key('distribution-selection'),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      '${songCountLabel(selected.count)} · ${distribution.shareLabel(selected.count)} библиотеки',
                      key: const Key('distribution-share'),
                      semanticsLabel:
                          '${selected.label}, ${songCountLabel(selected.count)}, ${distribution.shareLabel(selected.count)} библиотеки',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ScoreDistributionChart(
                      bands: bands,
                      selected: selected,
                      distribution: distribution,
                      onSelect: (band) =>
                          setState(() => selectedScore = band.low),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                bands.any((b) => b.low != b.high)
                    ? 'Большой разброс баллов объединён в диапазоны. Нажми на столбец или выбери диапазон сверху.'
                    : 'Нажми на столбец или выбери балл сверху, чтобы посмотреть число песен и их долю.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
