import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:obsidian_github_publisher/models/jekyll_theme.dart';
import 'package:obsidian_github_publisher/ui/editor/blog_preview.dart';

void main() {
  testWidgets('http 이미지 마크다운이 Image 위젯으로 렌더링된다', (tester) async {
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlogMarkdownBody(
              markdown: '![Image](https://github.com/user-attachments/assets/abc)\n문단\n\n![image](https://github.com/mohitto55/x/assets/1/2)\n## 제목',
              theme: JekyllTheme.fallback(''),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.textContaining('불러오지 못했습니다'), findsNothing);
    });
  });

  testWidgets('빈 주소는 안내 문구를 보여 준다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BlogMarkdownBody(markdown: '![image]()', theme: JekyllTheme.fallback(''))),
    ));
    await tester.pump();
    expect(find.textContaining('이미지 주소를 넣으세요'), findsOneWidget);
  });
}
