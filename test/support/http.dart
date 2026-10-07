import 'dart:convert';

import 'package:http/http.dart' as http;

/// A UTF-8 JSON response, the way the Gantry server sends it.
http.Response jsonResponse(String body,
    {int status = 200, Map<String, String> headers = const {}}) {
  return http.Response.bytes(
    utf8.encode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8', ...headers},
  );
}
