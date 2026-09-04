/// The current time, indirected once so tests can pin it.
///
/// Without this, anything that renders a date or a greeting is a moving
/// target: a golden taken this afternoon fails tomorrow morning, and a
/// month-boundary bug is only reproducible on the 31st. Production never
/// touches it — `DateTime.now` is the default and nothing reassigns it outside
/// a test.
library;

DateTime Function() clock = DateTime.now;

/// Pin the clock for the duration of a test. Returns the previous value so a
/// tearDown can put it back.
DateTime Function() useFixedClock(DateTime at) {
  final previous = clock;
  clock = () => at;
  return previous;
}
