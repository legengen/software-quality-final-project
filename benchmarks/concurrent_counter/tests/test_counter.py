from concurrent_counter import ConcurrentCounter


def test_initial_value_defaults_to_zero():
    counter = ConcurrentCounter()

    assert counter.value == 0


def test_sequential_increment_and_reset():
    counter = ConcurrentCounter(initial=2)

    assert counter.increment() == 3
    assert counter.increment(4) == 7
    counter.reset()

    assert counter.value == 0
