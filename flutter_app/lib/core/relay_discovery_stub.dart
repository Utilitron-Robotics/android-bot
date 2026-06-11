/// Web stub — browsers cannot send UDP. The picker shows this message and
/// the operator enters the relay IP manually (or uses a native build).
Future<List<String>> scanForRelays(
    {Duration timeout = const Duration(seconds: 2)}) async {
  throw UnsupportedError(
      'UDP relay scan is unavailable in the browser — enter the relay IP manually');
}
