import 'dart:async';

import 'package:mockito/mockito.dart';
import 'package:riverpod/src/internals.dart';
import 'package:state_notifier/state_notifier.dart';
import 'package:test/test.dart';

void main() {
  test("initState can't mark dirty other provider", () {
    final provider = SetStateProvider<Object>((ref) {
      return ref;
    });
    final container = ProviderContainer();
    final setStateRef =
        provider.readOwner(container) as SetStateProviderReference<Object>;

    final provider2 = Provider((_) {
      setStateRef.state = 42;
      return 0;
    });

    expect(setStateRef, isNotNull);

    expect(errorsOf(() => provider2.readOwner(container)), [isStateError]);
  });
  test("nested initState can't mark dirty other providers", () {
    final counter = Counter();
    final provider = StateNotifierProvider((_) => counter);
    final nested = Provider((_) => 0);
    final container = ProviderContainer();
    final provider2 = Provider((ref) {
      ref.dependOn(nested);
      counter.increment();
      return 0;
    });

    expect(provider.state.readOwner(container), 0);

    expect(errorsOf(() => provider2.readOwner(container)), [
      isStateError,
      isA<Error>(),
    ]);
  });

  test("dispose can't dirty anything", () {
    final counter = Counter();
    final provider = StateNotifierProvider((_) => counter);
    final root = ProviderContainer();
    List<Object> errors;
    final provider2 = Provider((ref) {
      ref.onDispose(() => errors = errorsOf(counter.increment));
      return 0;
    });
    final container = ProviderContainer(parent: root, overrides: [provider2]);

    expect(provider.state.readOwner(container), 0);
    expect(provider2.readOwner(container), 0);

    container.dispose();

    expect(errors, [isStateError, isA<Error>()]);
  });
  test(
      'watchOwner initial read cannot update the provider and its dependencies',
      () {
    final counter = Counter();
    final provider = StateNotifierProvider((_) => counter);
    final container = ProviderContainer();

    expect(provider.state.readOwner(container), 0);

    List<Object> errors;
    provider.state.watchOwner(container, (value) {
      errors = errorsOf(counter.increment);
    });

    expect(errors, [isA<AssertionError>(), isA<Error>()]);
  });
  test(
      'notifyListeners cannot dirty nodes that were already traversed across multiple ownwers',
      () {
    final counter = Counter();
    final provider = StateNotifierProvider((_) => counter);
    final root = ProviderContainer();
    final counter2 = Counter();
    final provider2 = StateNotifierProvider((_) => counter2);
    final container = ProviderContainer(
      parent: root,
      overrides: [provider2, provider2.state],
    );
    final listener = Listener();
    List<Object> errors;

    expect(provider.state.readOwner(container), 0);

    final sub = provider2.state.addLazyListener(
      container,
      mayHaveChanged: () {},
      onChange: (value) {
        listener(value);
        if (value > 0) {
          errors = errorsOf(counter.increment);
        }
      },
    );

    verify(listener(0)).called(1);
    verifyNoMoreInteractions(listener);

    counter.increment();
    counter2.increment();

    verifyNoMoreInteractions(listener);

    sub.flush();

    expect(errors, [isA<AssertionError>(), isA<Error>()]);
    verify(listener(1)).called(1);
    verifyNoMoreInteractions(listener);
  });

  test("Computed can't dirty anything on create", () {
    final counter = Counter();
    final provider = StateNotifierProvider((_) => counter);
    final container = ProviderContainer();
    List<Object> errors;
    final computed = Computed((read) {
      errors = errorsOf(counter.increment);
      return 0;
    });
    final listener = Listener();

    expect(provider.state.readOwner(container), 0);

    computed.watchOwner(container, listener);

    verify(listener(0)).called(1);
    verifyNoMoreInteractions(listener);
    expect(errors, [isA<StateError>(), isA<Error>()]);
  });
  test("Computed can't dirty anything on update", () {
    final counter = Counter();
    final provider = StateNotifierProvider((_) => counter);
    final container = ProviderContainer();
    List<Object> errors;
    final computed = Computed((read) {
      final value = read(provider.state);
      if (value > 0) {
        errors = errorsOf(counter.increment);
      }
      return value;
    });
    final listener = Listener();

    expect(provider.state.readOwner(container), 0);

    final sub = computed.addLazyListener(
      container,
      mayHaveChanged: () {},
      onChange: listener,
    );

    verify(listener(0)).called(1);
    verifyNoMoreInteractions(listener);
    expect(errors, isNull);

    counter.increment();
    verifyNoMoreInteractions(listener);

    sub.flush();

    verify(listener(1));
    verifyNoMoreInteractions(listener);
    expect(errors, [isA<StateError>(), isA<Error>()]);
  });
}

class Counter extends StateNotifier<int> {
  Counter() : super(0);

  void increment() => state++;
}

class Listener extends Mock {
  void call(int value);
}

List<Object> errorsOf(void Function() cb) {
  final errors = <Object>[];
  runZonedGuarded(cb, (err, _) => errors.add(err));
  return [...errors];
}
