import 'package:flutter/material.dart';

void showTranslationInfo(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Перевод текста'),
    content: const SingleChildScrollView(
      child: SelectableText(
        'Готовый построчный перевод Звука показывается под оригиналом. '
        'Если его нет, английский текст автоматически переводит Google Translate на телефоне. '
        'Первый языковой пакет (около 30 МБ) скачивается по Wi‑Fi. '
        'После этого перевод работает без интернета; текст не отправляется на сервер перевода.\n\n'
        'Это машинный перевод: он может неточно передавать сленг, игру слов и смысл песни. '
        'Google не предоставляет гарантий точности, надёжности, пригодности перевода или соблюдения прав третьих лиц.\n\n'
        'О переводе Google:\nhttps://translate.google.com\n'
        'https://cloud.google.com/translate',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Понятно'),
      ),
    ],
  ),
);

class TranslationAttribution extends StatelessWidget {
  const TranslationAttribution({super.key});
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      const Text('Автоперевод', style: TextStyle(fontSize: 12)),
      Image.asset(
        Theme.of(context).brightness == Brightness.dark
            ? 'assets/translation/white-regular@3x.png'
            : 'assets/translation/color-regular@3x.png',
        width: 176,
        height: 16,
        semanticLabel: 'powered by Google Translate',
      ),
      IconButton(
        tooltip: 'О переводе',
        icon: const Icon(Icons.info_outline_rounded, size: 18),
        onPressed: () => showTranslationInfo(context),
      ),
    ],
  );
}
