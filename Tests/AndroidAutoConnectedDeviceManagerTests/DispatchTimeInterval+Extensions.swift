import Dispatch

extension DispatchTimeInterval {
  /// Returns the equivalent representation of this `DispatchTimeInterval` in seconds
  ///
  /// If the given time interval is not provided in seconds, then a `fatalError` will occur.
  func toSeconds() -> Double {
    // Should only ever get defined in seconds.
    if case .seconds(let value) = self {
      return Double(value)
    }

    fatalError("This DispatchTimeInterval is not defined in seconds.")
  }
}
