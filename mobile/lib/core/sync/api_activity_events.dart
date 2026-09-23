import 'dart:async';

class ApiActivityEvents {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  Stream<void> get successes => _controller.stream;

  void notifySuccess() => _controller.add(null);

  Future<void> dispose() => _controller.close();
}
