// NOTE: This file is being completely replaced with a real WebRTC implementation.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:archive/archive.dart';

import 'grpc_client.dart';
import '../generated/robot_control.pb.dart';
import '../models/occupancy_grid.dart' as model;

/// WebRTC Transport for real-time data streaming (specifically for the map).
/// This implementation uses the existing gRPC stream for signaling.
class WebRtcTransport extends ChangeNotifier {
  static const String _tag = 'WebRtcTransport';

  final GrpcRobotClient _grpcClient;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  StreamSubscription? _grpcSignalSubscription;

  WebRtcState _state = WebRtcState.disconnected;
  WebRtcState get state => _state;
  bool get isConnected => _state == WebRtcState.connected;

  final _mapStreamController =
      StreamController<model.OccupancyGrid>.broadcast();
  Stream<model.OccupancyGrid> get mapStream => _mapStreamController.stream;

  // Depth camera image stream
  final _depthStreamController = StreamController<DepthImage>.broadcast();
  Stream<DepthImage> get depthStream => _depthStreamController.stream;

  // Additional streams and getters for unified_transport.dart compatibility
  final _stateStreamController = StreamController<WebRtcState>.broadcast();
  Stream<WebRtcState> get stateStream => _stateStreamController.stream;

  final _dataMessagesController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get dataMessages =>
      _dataMessagesController.stream;

  bool get hasDataChannel =>
      _dataChannel != null &&
      _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen;

  WebRtcTransport({required GrpcRobotClient grpcClient})
      : _grpcClient = grpcClient;

  Future<void> connect() async {
    if (_state == WebRtcState.connecting || _state == WebRtcState.connected) {
      debugPrint('$_tag: Already connected or connecting.');
      return;
    }
    _setState(WebRtcState.connecting);
    debugPrint('$_tag: Starting WebRTC connection for map stream...');

    // 1. Listen for signaling messages from the gRPC stream
    _grpcSignalSubscription =
        _grpcClient.webrtcSignalStream.listen(_handleServerSignal);

    // 2. Create PeerConnection
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    });

    _peerConnection!.onIceCandidate = (candidate) {
      debugPrint('$_tag: Got ICE candidate, sending to server...');
      final signal = WebRTCSignal()
        ..candidate = candidate.candidate!
        ..candidateMid = candidate.sdpMid!
        ..candidateMlineIndex = candidate.sdpMLineIndex!;
      _grpcClient.sendWebRtcSignal(signal);
    };

    _peerConnection!.onDataChannel = (channel) {
      debugPrint('$_tag: Received data channel: ${channel.label}');
      if (channel.label == 'map_data_channel') {
        _dataChannel = channel;
        _dataChannel!.onMessage = (message) {
          if (message.isBinary) {
            _handleMapData(message.binary);
          }
        };
        _dataChannel!.onDataChannelState = (state) {
          debugPrint('$_tag: Map data channel state: $state');
          if (state == RTCDataChannelState.RTCDataChannelOpen) {
            _setState(WebRtcState.connected);
          } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
            _setState(WebRtcState.disconnected);
          }
        };
      } else if (channel.label == 'depth_data_channel') {
        debugPrint('$_tag: Depth data channel received');
        channel.onMessage = (message) {
          if (message.isBinary) {
            _handleDepthData(message.binary);
          }
        };
        channel.onDataChannelState = (state) {
          debugPrint('$_tag: Depth data channel state: $state');
        };
      }
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('$_tag: PeerConnection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        disconnect();
      }
    };

    // 3. Send request to start the stream
    debugPrint('$_tag: Sending request for map stream...');
    _grpcClient.requestMapStream();
  }

  void _handleServerSignal(WebRTCSignal signal) {
    if (_peerConnection == null) return;

    if (signal.hasSdp()) {
      final sdp = RTCSessionDescription(signal.sdp, 'offer');
      debugPrint('$_tag: Received SDP offer, setting remote description...');
      _peerConnection!.setRemoteDescription(sdp).then((_) async {
        debugPrint('$_tag: Creating SDP answer...');
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        debugPrint('$_tag: Sending SDP answer...');
        final responseSignal = WebRTCSignal()..sdp = answer.sdp!;
        _grpcClient.sendWebRtcSignal(responseSignal);
      }).catchError((e) {
        debugPrint(
            '$_tag: Failed to set remote description or create answer: $e');
      });
    } else if (signal.hasCandidate()) {
      debugPrint('$_tag: Received ICE candidate, adding...');
      final candidate = RTCIceCandidate(
        signal.candidate,
        signal.candidateMid,
        signal.candidateMlineIndex,
      );
      _peerConnection!.addCandidate(candidate);
    }
  }

  void _handleMapData(Uint8List compressedData) {
    try {
      // Decompress the data (assuming ZLIB/Deflate from the server)
      final decompressed = Inflate(compressedData).getBytes();

      // TODO: A real implementation needs to parse the full OccupancyGrid message.
      // This requires a binary serialization format (like Protobuf bytes) instead
      // of just the raw grid data. For now, we assume the binary data IS the grid.
      final gridData = decompressed.map((byte) => byte.toInt()).toList();

      final map = model.OccupancyGrid(
        // This metadata should also be part of the binary message.
        info: model.MapInfo(
          resolution: 0.05,
          width: 384,
          height: 384,
          origin: model.Pose(
            position: model.Point(x: -10.0, y: -10.0, z: 0.0),
            orientation: model.Quaternion(x: 0, y: 0, z: 0, w: 1),
          ),
        ),
        data: gridData,
      );
      _mapStreamController.add(map);
    } catch (e) {
      debugPrint('$_tag: Failed to decompress or parse map data: $e');
    }
  }

  void _handleDepthData(Uint8List packet) {
    try {
      // Parse header: [width:2][height:2][encoding_len:1][encoding:N][data...]
      if (packet.length < 5) return;

      final width = (packet[0] << 8) | packet[1];
      final height = (packet[2] << 8) | packet[3];
      final encodingLen = packet[4];

      if (packet.length < 5 + encodingLen) return;

      final encoding = String.fromCharCodes(packet.sublist(5, 5 + encodingLen));
      final imageData = packet.sublist(5 + encodingLen);

      debugPrint('$_tag: Received depth image: ${width}x$height $encoding (${imageData.length} bytes)');

      _depthStreamController.add(DepthImage(
        width: width,
        height: height,
        encoding: encoding,
        data: Uint8List.fromList(imageData),
      ));
    } catch (e) {
      debugPrint('$_tag: Failed to parse depth data: $e');
    }
  }

  Future<void> disconnect() async {
    debugPrint('$_tag: Disconnecting...');
    await _grpcSignalSubscription?.cancel();
    _grpcSignalSubscription = null;
    await _dataChannel?.close();
    await _peerConnection?.close();
    _peerConnection = null;
    _setState(WebRtcState.disconnected);
  }

  void _setState(WebRtcState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateStreamController.add(newState);
    notifyListeners();
  }

  /// Create an SDP offer for video streaming (used by unified_transport.dart)
  Future<RTCSessionDescription?> createOffer() async {
    if (_peerConnection == null) {
      debugPrint('$_tag: Cannot create offer - no peer connection');
      return null;
    }
    try {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      return offer;
    } catch (e) {
      debugPrint('$_tag: Failed to create offer: $e');
      return null;
    }
  }

  /// Send velocity command over data channel (for low-latency teleoperation)
  void sendVelocity(double linear, double angular) {
    sendData({
      'type': 'velocity',
      'linear': linear,
      'angular': angular,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Send arbitrary data over the data channel
  void sendData(Map<String, dynamic> data) {
    if (_dataChannel == null ||
        _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      debugPrint('$_tag: Cannot send data - data channel not open');
      return;
    }
    try {
      final jsonString = data.toString(); // Simple encoding
      final bytes = Uint8List.fromList(jsonString.codeUnits);
      _dataChannel!.send(RTCDataChannelMessage.fromBinary(bytes));
    } catch (e) {
      debugPrint('$_tag: Failed to send data: $e');
    }
  }

  @override
  void dispose() {
    disconnect();
    _mapStreamController.close();
    _depthStreamController.close();
    _stateStreamController.close();
    _dataMessagesController.close();
    super.dispose();
  }
}

enum WebRtcState {
  disconnected,
  connecting,
  connected,
  failed,
}

/// Depth camera image data
class DepthImage {
  final int width;
  final int height;
  final String encoding;
  final Uint8List data;

  DepthImage({
    required this.width,
    required this.height,
    required this.encoding,
    required this.data,
  });
}
