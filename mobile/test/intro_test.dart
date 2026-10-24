import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stemik/ui/intro.dart';

void main() {
  testWidgets('the intro plays over the app, then leaves only the app', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LaunchIntro(child: Text('app'))));
    // Artwork can't decode under the test clock: the intro starts once the
    // 600 ms wait for it runs out.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('app'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.image(const AssetImage('assets/brand/intro-base.png')), findsOneWidget);

    // Mid-wink.
    await tester.pump(const Duration(milliseconds: 1150));
    expect(find.image(const AssetImage('assets/brand/intro-base.png')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.image(const AssetImage('assets/brand/intro-base.png')), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('a tap skips to the end', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LaunchIntro(child: Text('app'))));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.image(const AssetImage('assets/brand/intro-base.png')), findsNothing);
  });

  testWidgets('not shown when the system asks for reduced motion', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: LaunchIntro(child: Text('app'))),
      ),
    );
    expect(find.image(const AssetImage('assets/brand/intro-base.png')), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });
}
