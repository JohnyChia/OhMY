import 'package:community_discovery/community_discovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../community_discovery/test/support/fake_community_repository.dart';

void main() {
  testWidgets('Community can mount while Home listens to the same controller', (
    tester,
  ) async {
    final controller = CommunityController(FakeCommunityRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: IndexedStack(
          children: [
            AnimatedBuilder(
              animation: controller,
              builder: (_, _) => Text('${controller.tags.length} tags'),
            ),
            CommunityFeedScreen(
              controller: controller,
              showBottomNavigation: false,
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(controller.tags, isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
