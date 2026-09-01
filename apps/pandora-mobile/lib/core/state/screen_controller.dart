import 'package:flutter/foundation.dart';

import '../data/pandora_repository.dart';
import '../network/pandora_api_error.dart';
import 'loadable.dart';

typedef ScreenLoader<T> = Future<RepositorySnapshot<T>> Function();

class ScreenController<T> extends ChangeNotifier {
  ScreenController(this._loader, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final ScreenLoader<T> _loader;
  final DateTime Function() _clock;

  Loadable<T> _state = LoadableInitial<T>();
  var _generation = 0;
  var _disposed = false;

  Loadable<T> get state => _state;
  RepositorySnapshot<T>? get snapshot => _state.snapshot;
  T? get data => snapshot?.data;
  PandoraRepositoryException? get error => _state.error;
  bool get isLoading => _state.isLoading;
  bool get isCached => snapshot?.isCached ?? false;
  bool get isStale => snapshot?.isStaleAt(_clock()) ?? false;
  String? get degradedReason => snapshot?.degradedReason;
  String? get requestId => snapshot?.requestId ?? error?.requestId;

  Future<void> load() => _run();

  Future<void> refresh() => _run();

  Future<void> _run() async {
    if (_disposed) return;
    final generation = ++_generation;
    final previous = _state.snapshot;
    _state = LoadableLoading<T>(previous: previous);
    notifyListeners();
    try {
      final result = await _loader();
      if (!_isCurrent(generation)) return;
      _state = LoadableSuccess<T>(result);
    } on PandoraRepositoryException catch (error) {
      if (!_isCurrent(generation)) return;
      _state = LoadableFailure<T>(
        failure: error,
        previous: _mayRetainPrevious(error) ? previous : null,
      );
    } catch (_) {
      if (!_isCurrent(generation)) return;
      _state = LoadableFailure<T>(
        failure: const PandoraApiError(
          kind: PandoraApiErrorKind.contract,
          message: 'Pandora could not safely read that response.',
          code: 'UNEXPECTED_REPOSITORY_FAILURE',
        ),
        previous: previous,
      );
    }
    if (_isCurrent(generation)) notifyListeners();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  bool _mayRetainPrevious(PandoraRepositoryException error) =>
      switch (error.kind) {
        PandoraApiErrorKind.sessionExpired ||
        PandoraApiErrorKind.forbidden =>
          false,
        _ => true,
      };

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}
