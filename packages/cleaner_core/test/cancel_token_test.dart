import 'package:cleaner_core/cleaner_core.dart';
import 'package:test/test.dart';

void main() {
  test('cancel() sets the flag', () {
    final t = CancelToken();
    expect(t.isCancelled, isFalse);
    t.cancel();
    expect(t.isCancelled, isTrue);
  });

  test('probe is consulted on every check', () {
    var external = false;
    final t = CancelToken(() => external);
    expect(t.isCancelled, isFalse);
    external = true;
    expect(t.isCancelled, isTrue);
  });
}
