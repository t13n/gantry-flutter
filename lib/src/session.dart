/// The targeted interstitial last received for the current customer.
class TargetedCache {
  /// Creates a cache entry.
  const TargetedCache({required this.etag, required this.body});

  /// ETag to revalidate with.
  final String etag;

  /// The response body the ETag belongs to.
  final String body;
}

/// Who is signed in, plus everything that must be forgotten when that changes.
class Session {
  static final RegExp _customerIdFormat = RegExp(r'^[A-Za-z0-9_\-.:]{1,64}$');

  String? _customerId;
  int _generation = 0;

  /// The cached targeted interstitial of the current customer.
  TargetedCache? targeted;

  /// The current customer id, or null when nobody is signed in.
  String? get customerId => _customerId;

  /// Changes every time the customer changes. A request compares the value
  /// before and after to discard an answer meant for the previous customer.
  int get generation => _generation;

  /// Sets the current customer. Throws an [ArgumentError] for a malformed id.
  void identify(String customerId) {
    if (!_customerIdFormat.hasMatch(customerId)) {
      // The value is left out on purpose: errors end up in crash reports.
      throw ArgumentError(
        'must be 1 to 64 letters, digits or _ - . :',
        'customerId',
      );
    }
    if (customerId == _customerId) return;
    _customerId = customerId;
    _forget();
  }

  /// Clears the current customer and their cached data.
  void reset() {
    _customerId = null;
    _forget();
  }

  void _forget() {
    _generation++;
    targeted = null;
  }
}
