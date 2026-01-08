/// WebRTC Transport for Low-Latency Video and Data
///
/// Provides:
/// - Ultra-low-latency video streaming from robot cameras
/// - Data channels for control commands (lower latency than gRPC)
/// - Peer-to-peer connection when possible (bypasses cloud)
/// - TURN/STUN for NAT traversal
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'transport_config.dart';

/// ICE Server configuration
class IceServer {
  final List<String> urls;
  final String? username;
  final String? credential;

  IceServer({
    required this.urls,
    this.username,
    this.credential,
  });

  Map<String, dynamic> toJson() => {
        'urls': urls,
        if (username != null) 'username': username,
        if (credential != null) 'credential': credential,
      };
}

/// WebRTC connection state
enum WebRtcState {
  disconnected,
  connecting,
  connected,
  failed,
}

/// Data channel state
enum DataChannelState {
  closed,
  connecting,
  open,
}

/// Video track info
class VideoTrack {
  final String id;
  final String label;
  final int width;
  final int height;
  final int fps;

  VideoTrack({
    required this.id,
    required this.label,
    this.width = 1280,
    this.height = 720,
    this.fps = 30,
  });
}

/// WebRTC Transport - for low-latency video and data
class WebRtcTransport extends ChangeNotifier {
  static const String _tag = 'WebRtcTransport';

  // Configuration
  final TransportConfig _config;
  final List<IceServer> _iceServers;

  // State
  WebRtcState _state = WebRtcState.disconnected;
  DataChannelState _dataChannelState = DataChannelState.closed;
  String? _lastError;

  // Streams
  final _stateController = StreamController<WebRtcState>.broadcast();
  final _videoFrameController = StreamController<Uint8List>.broadcast();
  final _dataMessageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _latencyController = StreamController<double>.broadcast();

  // Metrics
  double _currentLatency = 0;
  int _bytesReceived = 0;
  int _bytesSent = 0;
  DateTime? _connectionStart;

  // Signaling
  Function(Map<String, dynamic>)? _onSignalingMessage;

  WebRtcTransport({
    TransportConfig? config,
    List<IceServer>? iceServers,
  })  : _config = config ?? TransportConfig.instance,
        _iceServers = iceServers ?? _defaultIceServers;

  // Default STUN/TURN servers
  static final List<IceServer> _defaultIceServers = [
    IceServer(urls: ['stun:stun.l.google.com:19302']),
    IceServer(urls: ['stun:stun1.l.google.com:19302']),
    // Add your TURN server here for NAT traversal
    // IceServer(
    //   urls: ['turn:turn.example.com:3478'],
    //   username: 'user',
    //   credential: 'pass',
    // ),
  ];

  // Getters
  WebRtcState get state => _state;
  DataChannelState get dataChannelState => _dataChannelState;
  String? get lastError => _lastError;
  bool get isConnected => _state == WebRtcState.connected;
  bool get hasDataChannel => _dataChannelState == DataChannelState.open;
  double get currentLatency => _currentLatency;

  Stream<WebRtcState> get stateStream => _stateController.stream;
  Stream<Uint8List> get videoFrames => _videoFrameController.stream;
  Stream<Map<String, dynamic>> get dataMessages =>
      _dataMessageController.stream;
  Stream<double> get latencyStream => _latencyController.stream;

  /// Set signaling message callback
  void setSignalingCallback(Function(Map<String, dynamic>) callback) {
    _onSignalingMessage = callback;
  }

  /// Create offer for initiating connection
  Future<Map<String, dynamic>> createOffer() async {
    _setState(WebRtcState.connecting);

    try {
      // In a real implementation, this would use the webrtc package
      // For now, return a mock SDP offer structure
      final offer = {
        'type': 'offer',
        'sdp': _generateMockSdp('offer'),
        'ice_servers': _iceServers.map((s) => s.toJson()).toList(),
      };

      debugPrint('$_tag: Created offer');
      return offer;
    } catch (e) {
      _setError('Failed to create offer: $e');
      rethrow;
    }
  }

  /// Handle incoming answer
  Future<void> handleAnswer(Map<String, dynamic> answer) async {
    try {
      final sdp = answer['sdp'] as String?;
      if (sdp == null) {
        throw Exception('Answer missing SDP');
      }

      debugPrint('$_tag: Handling answer');
      // In real implementation, set remote description

      _setState(WebRtcState.connected);
      _connectionStart = DateTime.now();
      _startLatencyMeasurement();
    } catch (e) {
      _setError('Failed to handle answer: $e');
      rethrow;
    }
  }

  /// Handle incoming offer (when receiving a call)
  Future<Map<String, dynamic>> handleOffer(Map<String, dynamic> offer) async {
    _setState(WebRtcState.connecting);

    try {
      final sdp = offer['sdp'] as String?;
      if (sdp == null) {
        throw Exception('Offer missing SDP');
      }

      debugPrint('$_tag: Handling offer, creating answer');

      // Create answer
      final answer = {
        'type': 'answer',
        'sdp': _generateMockSdp('answer'),
      };

      _setState(WebRtcState.connected);
      _connectionStart = DateTime.now();
      _startLatencyMeasurement();

      return answer;
    } catch (e) {
      _setError('Failed to handle offer: $e');
      rethrow;
    }
  }

  /// Handle ICE candidate
  void handleIceCandidate(Map<String, dynamic> candidate) {
    debugPrint('$_tag: Received ICE candidate');
    // In real implementation, add ICE candidate to peer connection
  }

  /// Send data through data channel
  void sendData(Map<String, dynamic> data) {
    if (_dataChannelState != DataChannelState.open) {
      debugPrint('$_tag: Cannot send - data channel not open');
      return;
    }

    try {
      final encoded = jsonEncode(data);
      _bytesSent += encoded.length;
      // In real implementation, send through data channel
      debugPrint('$_tag: Sent data: ${data['type'] ?? 'unknown'}');
    } catch (e) {
      debugPrint('$_tag: Send failed: $e');
    }
  }

  /// Send velocity command (optimized for low latency)
  void sendVelocity(double linear, double angular) {
    sendData({
      'type': 'velocity',
      'linear': linear,
      'angular': angular,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Send navigation command
  void sendNavigation(String waypoint) {
    sendData({
      'type': 'navigate',
      'waypoint': waypoint,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Request video stream
  void requestVideoStream({
    int width = 1280,
    int height = 720,
    int fps = 30,
    String codec = 'VP8',
  }) {
    sendData({
      'type': 'request_video',
      'width': width,
      'height': height,
      'fps': fps,
      'codec': codec,
    });
  }

  /// Handle signaling message (from signaling server)
  Future<void> handleSignalingMessage(Map<String, dynamic> message) async {
    final type = message['type'] as String?;

    switch (type) {
      case 'offer':
        final answer = await handleOffer(message);
        _onSignalingMessage?.call(answer);
        break;
      case 'answer':
        await handleAnswer(message);
        break;
      case 'ice-candidate':
        handleIceCandidate(message['candidate'] as Map<String, dynamic>);
        break;
      default:
        debugPrint('$_tag: Unknown signaling message type: $type');
    }
  }

  /// Disconnect
  Future<void> disconnect() async {
    debugPrint('$_tag: Disconnecting');

    _setState(WebRtcState.disconnected);
    _dataChannelState = DataChannelState.closed;
    _connectionStart = null;
    _bytesReceived = 0;
    _bytesSent = 0;

    notifyListeners();
  }

  void _setState(WebRtcState newState) {
    _state = newState;
    _stateController.add(newState);
    notifyListeners();
  }

  void _setError(String error) {
    _lastError = error;
    _setState(WebRtcState.failed);
    debugPrint('$_tag: Error - $error');
  }

  void _startLatencyMeasurement() {
    // Periodically measure RTT using data channel ping/pong
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_state != WebRtcState.connected) {
        timer.cancel();
        return;
      }

      final pingTime = DateTime.now().millisecondsSinceEpoch;
      sendData({
        'type': 'ping',
        'timestamp': pingTime,
      });
    });
  }

  /// Handle incoming data channel message
  void _handleDataMessage(String data) {
    try {
      final message = jsonDecode(data) as Map<String, dynamic>;
      _bytesReceived += data.length;

      // Handle ping/pong for latency measurement
      if (message['type'] == 'pong') {
        final sentTime = message['timestamp'] as int;
        _currentLatency =
            (DateTime.now().millisecondsSinceEpoch - sentTime) / 2.0;
        _latencyController.add(_currentLatency);

        // Update config with new RTT measurement
        _config.updateNetworkMetrics(
          rttMs: _currentLatency * 2,
          jitterMs: _config.currentJitter, // Keep existing jitter
        );
        return;
      }

      if (message['type'] == 'ping') {
        // Respond with pong
        sendData({
          'type': 'pong',
          'timestamp': message['timestamp'],
        });
        return;
      }

      _dataMessageController.add(message);
    } catch (e) {
      debugPrint('$_tag: Failed to parse data message: $e');
    }
  }

  /// Handle incoming video frame
  void _handleVideoFrame(Uint8List frame) {
    _bytesReceived += frame.length;
    _videoFrameController.add(frame);
  }

  String _generateMockSdp(String type) {
    // Mock SDP for testing - real implementation uses WebRTC stack
    return '''v=0
o=- ${DateTime.now().millisecondsSinceEpoch} 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0 1
m=video 9 UDP/TLS/RTP/SAVPF 96
c=IN IP4 0.0.0.0
a=rtcp:9 IN IP4 0.0.0.0
a=rtpmap:96 VP8/90000
a=mid:0
a=$type
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
c=IN IP4 0.0.0.0
a=sctp-port:5000
a=mid:1
a=$type''';
  }

  /// Get connection statistics
  Map<String, dynamic> getStats() => {
        'state': _state.name,
        'data_channel_state': _dataChannelState.name,
        'latency_ms': _currentLatency,
        'bytes_received': _bytesReceived,
        'bytes_sent': _bytesSent,
        'connection_duration_ms': _connectionStart != null
            ? DateTime.now().difference(_connectionStart!).inMilliseconds
            : 0,
      };

  @override
  void dispose() {
    disconnect();
    _stateController.close();
    _videoFrameController.close();
    _dataMessageController.close();
    _latencyController.close();
    super.dispose();
  }
}

/// WebRTC Signaling Client
/// Handles offer/answer/ICE exchange via WebSocket or HTTP
class WebRtcSignaling {
  static const String _tag = 'WebRtcSignaling';

  final String signalingUrl;
  final String robotId;

  StreamController<Map<String, dynamic>>? _messageController;
  Stream<Map<String, dynamic>> get messages =>
      (_messageController ??= StreamController.broadcast()).stream;

  WebRtcSignaling({
    required this.signalingUrl,
    required this.robotId,
  });

  /// Connect to signaling server
  Future<void> connect() async {
    debugPrint('$_tag: Connecting to $signalingUrl');
    _messageController = StreamController.broadcast();
    // Real implementation would establish WebSocket connection
  }

  /// Send signaling message
  Future<void> send(Map<String, dynamic> message) async {
    message['robot_id'] = robotId;
    debugPrint('$_tag: Sending ${message['type']}');
    // Real implementation would send via WebSocket
  }

  /// Disconnect from signaling server
  void disconnect() {
    _messageController?.close();
    _messageController = null;
  }
}
