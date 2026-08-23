import '../data/pandora_repository.dart';

sealed class Loadable<T> {
  const Loadable();

  RepositorySnapshot<T>? get snapshot;

  PandoraRepositoryException? get error => null;

  bool get isLoading => false;
}

final class LoadableInitial<T> extends Loadable<T> {
  const LoadableInitial();

  @override
  RepositorySnapshot<T>? get snapshot => null;
}

final class LoadableLoading<T> extends Loadable<T> {
  const LoadableLoading({this.previous});

  final RepositorySnapshot<T>? previous;

  @override
  RepositorySnapshot<T>? get snapshot => previous;

  @override
  bool get isLoading => true;
}

final class LoadableSuccess<T> extends Loadable<T> {
  const LoadableSuccess(this.value);

  final RepositorySnapshot<T> value;

  @override
  RepositorySnapshot<T> get snapshot => value;
}

final class LoadableFailure<T> extends Loadable<T> {
  const LoadableFailure({required this.failure, this.previous});

  final PandoraRepositoryException failure;
  final RepositorySnapshot<T>? previous;

  @override
  RepositorySnapshot<T>? get snapshot => previous;

  @override
  PandoraRepositoryException get error => failure;
}
