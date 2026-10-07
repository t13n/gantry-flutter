/// Base type of every failure the SDK reports by throwing.
///
/// The type is sealed, so a `switch` over it is checked for completeness.
sealed class GantryException implements Exception {
  /// Creates an exception with a human-readable [message].
  const GantryException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => '$_name: $message';

  // Written out because runtimeType is minified in obfuscated builds.
  String get _name => switch (this) {
        GantryNetworkException() => 'GantryNetworkException',
        GantryUnauthorizedException() => 'GantryUnauthorizedException',
        GantryRateLimitedException() => 'GantryRateLimitedException',
        GantryServerException() => 'GantryServerException',
        GantryRequestException() => 'GantryRequestException',
        GantryNotIdentifiedException() => 'GantryNotIdentifiedException',
      };
}

/// The server could not be reached or did not answer in time.
final class GantryNetworkException extends GantryException {
  /// Creates a network failure, optionally keeping the underlying [cause].
  const GantryNetworkException(super.message, {this.cause});

  /// The underlying error, if any.
  final Object? cause;
}

/// The API key is missing, wrong or revoked (HTTP 401).
final class GantryUnauthorizedException extends GantryException {
  /// Creates an unauthorized failure.
  const GantryUnauthorizedException() : super('The API key was rejected');
}

/// Too many requests in a short time (HTTP 429).
final class GantryRateLimitedException extends GantryException {
  /// Creates a rate-limit failure.
  const GantryRateLimitedException()
      : super('Too many requests; try again shortly');
}

/// The server failed or answered in a way this SDK version does not expect.
final class GantryServerException extends GantryException {
  /// Creates a server failure for [statusCode].
  const GantryServerException(this.statusCode,
      [super.message = 'The server returned an unexpected response']);

  /// The HTTP status code of the response.
  final int statusCode;

  @override
  String toString() => '${super.toString()} (HTTP $statusCode)';
}

/// The server rejected the request (HTTP 400).
///
/// The SDK validates formats before sending, so in practice this means the
/// campaign id is not known to Gantry.
final class GantryRequestException extends GantryException {
  /// Creates a rejected-request failure.
  const GantryRequestException() : super('The server rejected the request');
}

/// A call that needs a customer was made before `Gantry.identify`.
final class GantryNotIdentifiedException extends GantryException {
  /// Creates a not-identified failure.
  const GantryNotIdentifiedException()
      : super('Call identify() with the customer id first');
}
