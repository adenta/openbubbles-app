import 'dart:async';
import 'package:bluebubbles/helpers/files/serial_work_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an exception or empty image cannot stall subsequent work', () async {
    final queue = SerialWorkQueue();
    final gate = Completer<void>();
    final order = <int>[];
    final bad = queue.run(() async {
      await gate.future;
      order.add(1);
      throw StateError('invalid image');
    });
    final failed = expectLater(bad, throwsStateError);
    final empty = queue.run(() async {
      order.add(2);
      return <int>[];
    });
    final good = queue.run(() async {
      order.add(3);
      return [1, 2, 3];
    });
    expect(order, isEmpty);
    gate.complete();
    await failed;
    expect(await empty, isEmpty);
    expect(await good, [1, 2, 3]);
    expect(order, [1, 2, 3]);
  });
}
