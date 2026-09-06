import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제 네트워크로 GitHub 첨부 이미지를 NetworkImage 가 읽을 수 있는지 확인 (진단용)
/// flutter test test/editor/network_image_live_test.dart --dart-define=LIVE=true
void main() {
  const live = bool.fromEnvironment('LIVE');
  testWidgets('GitHub 첨부 이미지를 NetworkImage 로 받는다', (tester) async {
    HttpOverrides.global = null; // flutter_test 의 400 mock 해제
    const urls = [
      'https://github.com/user-attachments/assets/bc7c2d87-456d-4924-b358-7f9999f31815',
      'https://github.com/mohitto55/mohitto55.github.io/assets/154340583/078f4e07-fb3f-42f3-beb8-47f0b7f0c9c8',
    ];
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    for (final url in urls) {
      Object? error;
      await tester.runAsync(() async {
        try {
          await precacheImage(NetworkImage(url), context, onError: (e, _) => error = e).timeout(const Duration(seconds: 20));
        } catch (e) {
          error = e;
        }
      });
      // ignore: avoid_print
      print('$url -> ${error ?? 'OK'}');
      expect(error, isNull, reason: url);
    }
  }, skip: !live);
}
