/// A failed job must never prevent the next image from loading.
class SerialWorkQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
