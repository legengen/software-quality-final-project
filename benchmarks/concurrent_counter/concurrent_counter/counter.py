import time


class ConcurrentCounter:
    """A small counter used to demonstrate thread-safety repairs."""

    def __init__(self, initial=0):
        self._value = initial

    @property
    def value(self):
        return self._value

    def increment(self, amount=1):
        """Increase the counter by amount and return the new value.

        This implementation is intentionally not thread-safe: two threads can
        read the same old value and then overwrite each other's update.
        """
        old_value = self._value
        time.sleep(0.00001)
        self._value = old_value + amount
        return self._value

    def reset(self):
        self._value = 0
