import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/ai_chatbot/services/nova_silence_cutoff.dart';

void main() {
  testWidgets('initial silence and pauses cut off at one second', (
    tester,
  ) async {
    var stops = 0;
    final cutoff = NovaSilenceCutoff(() => stops++);
    cutoff.arm();
    await tester.pump(const Duration(milliseconds: 999));
    expect(stops, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(stops, 1);
    cutoff.arm();
    await tester.pump(const Duration(milliseconds: 700));
    cutoff.arm(); // speech extends the recording
    await tester.pump(const Duration(milliseconds: 999));
    expect(stops, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(stops, 2);
    cutoff.arm();
    cutoff.cancel();
    await tester.pump(const Duration(seconds: 2));
    expect(stops, 2);
  });
}
