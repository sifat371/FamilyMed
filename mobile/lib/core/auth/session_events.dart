import 'dart:async';

class SessionEvents {
  final StreamController<void> _expiredController = StreamController<void>.broadcast();

  Stream<void> get expired => _expiredController.stream;

  void notifyExpired() {
    if (!_expiredController.isClosed) {
      _expiredController.add(null);
    }
  }

  void dispose() {
    _expiredController.close();
  }
}
