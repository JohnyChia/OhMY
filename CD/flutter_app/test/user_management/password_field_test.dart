import 'package:flutter/material.dart';
import 'package:flutter_app/user_management/widgets/password_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty password field has no bullet placeholder', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasswordField(
            controller: controller,
            label: 'New password',
            validator: (_) => null,
          ),
        ),
      ),
    );

    final decorator = tester.widget<InputDecorator>(
      find.byType(InputDecorator),
    );
    expect(decorator.decoration.hintText, isNull);
  });

  testWidgets('eye icon matches whether password is hidden or visible', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Password123');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasswordField(
            controller: controller,
            label: 'New password',
            validator: (_) => null,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
  });
}
