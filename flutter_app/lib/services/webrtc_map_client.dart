// NOTE: This file is written assuming the protobuf classes have been regenerated
// after the .proto file modification. The build process must be run for this
// code to compile.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:archive/archive.dart';

import '../core/grpc_client.dart';
import '../generated/robot_control.pb.dart';
import '../models/occupancy_grid.dart' as model;

class WebRtcMapClient {
  final GrpcRobotClient _grpcClient;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  StreamSubscription? _grpcSignalSubscription;
  StreamSubscription? _dataChannelSubscription;

  final _mapStreamController = StreamController<model.OccupancyGrid>();
  Stream<model.OccupancyGrid> get mapStream => _mapStreamController.stream;

  WebRtcMapClient(this._grpcClient);

  Future<void> connect() async {
    if (_peerConnection != null) {
      debugPrint('WebRtcMapClient: Already connected or connecting.');
      return;
    }

    // 1. Listen for signaling messages from the gRPC stream
    _grpcSignalSubscription = _grpcClient.webrtcSignalStream.listen((signal) {
      _handleServerSignal(signal);
    });

    // 2. Create PeerConnection
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    }, {});

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate != null) {
        debugPrint('WebRtcMapClient: Got ICE candidate, sending to server...');
        final signal = WebRTCSignal()
          ..candidate = candidate.candidate!
          ..candidateMid = candidate.sdpMid!
          ..candidateMlineIndex = candidate.sdpMLineIndex!;
        _grpcClient.sendWebRtcSignal(signal);
      }
    };

    _peerConnection!.onDataChannel = (channel) {
      debugPrint('WebRtcMapClient: Received data channel: ${channel.label}');
      if (channel.label == 'map_data_channel') {
        _dataChannel = channel;
        _dataChannel!.onMessage = (message) {
          if (message.isBinary) {
            _handleMapData(message.binary);
          }
        };
      }
    };

    // 3. Send request to start the stream
    debugPrint('WebRtcMapClient: Sending request for map stream...');
    _grpcClient.requestMapStream();
  }

  void _handleServerSignal(WebRTCSignal signal) {
    if (signal.hasSdp()) {
      final sdp = RTCSessionDescription(signal.sdp, 'offer');
      debugPrint('WebRtcMapClient: Received SDP offer, setting remote description...');
      _peerConnection?.setRemoteDescription(sdp).then((_) async {
        debugPrint('WebRtcMapClient: Creating SDP answer...');
        final answer = await _peerConnection!.createAnswer({});
        await _peerConnection!.setLocalDescription(answer);
        debugPrint('WebRtcMapClient: Sending SDP answer...');
        final responseSignal = WebRTCSignal()..sdp = answer.sdp!;
        _grpcClient.sendWebRtcSignal(responseSignal);
      });
    } else if (signal.hasCandidate()) {
      debugPrint('WebRtcMapClient: Received ICE candidate, adding...');
      final candidate = RTCIceCandidate(
        signal.candidate,
        signal.candidateMid,
        signal.candidateMlineIndex,
      );
      _peerConnection?.addCandidate(candidate);
    }
  }

  void _handleMapData(Uint8List compressedData) {
    try {
      // Decompress the data (assuming ZLIB/Deflate)
      final decompressed = Inflate(compressedData).getBytes();
      
      // TODO: Here you would parse the binary data into the OccupancyGrid model.
      // This is a placeholder as the exact binary format would need to be defined.
      // For now, we'll assume it's just the raw grid data.
      final gridData = decompressed.map((byte) => byte.toInt()).toList();

      final map = model.OccupancyGrid(
        info: model.MapInfo( // Using placeholder info for now
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
      debugPrint('WebRtcMapClient: Failed to decompress or parse map data: $e');
    }
  }

  void dispose() {
    debugPrint('WebRtcMapClient: Disposing...');
    _grpcSignalSubscription?.cancel();
    _dataChannelSubscription?.cancel();
    _dataChannel?.close();
    _peerConnection?.close();
    _peerConnection = null;
    _mapStreamController.close();
  }
}
