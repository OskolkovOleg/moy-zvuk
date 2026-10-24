import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const captureKey = Key('ui-capture');

Future<void> loadUiFonts() async {
  if (Platform.environment['ZVUK_UI_CAPTURE_DIR'] == null) return;
  final sdk = Platform.environment['FLUTTER_ROOT'];
  if (sdk == null) return;
  final loader = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final file = File(
      '$sdk/bin/cache/artifacts/material_fonts/Roboto-$weight.ttf',
    );
    if (await file.exists()) {
      loader.addFont(
        file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
    }
  }
  await loader.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)),
    );
  await icons.load();
}

Future<void> captureUi(WidgetTester tester, String name) async {
  final directory = Platform.environment['ZVUK_UI_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/brand/icon.png'),
      tester.element(find.byType(MaterialApp).first),
    ),
  );
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final output = Directory(directory);
    await output.create(recursive: true);
    await File('${output.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}
