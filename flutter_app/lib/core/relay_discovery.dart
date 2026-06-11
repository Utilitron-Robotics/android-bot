import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// UDP relay discovery — speaks the protocol the relay's DiscoveryService
/// already implements: broadcast UTILITRON_RELAY_DISCOVER on :9999, collect
/// UTILITRON_RELAY_RESPONSE unicasts. Works on any subnet (no hardcoded
/// ranges — networks change per floor). Native platforms only; the web
/// build uses relay_discovery_stub.dart via conditional import.
const int _discoveryPort = 9999;
const String _discoveryRequest = 'UTILITRON_RELAY_DISCOVER';
const String _discoveryResponseType = 'UTILITRON_RELAY_RESPONSE';

Future<List<String>> scanForRelays(
    {Duration timeout = const Duration(seconds: 2)}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;
  final found = <String>{};

  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    try {
      final json = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (json['type'] == _discoveryResponseType) {
        found.add(dg.address.address);
      }
    } catch (_) {
      // Not a relay response — ignore
    }
  });

  socket.send(utf8.encode(_discoveryRequest),
      InternetAddress('255.255.255.255'), _discoveryPort);

  await Future<void>.delayed(timeout);
  await sub.cancel();
  socket.close();
  return found.toList();
}
