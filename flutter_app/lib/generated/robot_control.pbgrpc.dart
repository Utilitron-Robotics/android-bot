// This is a generated file - do not edit.
//
// Generated from robot_control.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'robot_control.pb.dart' as $0;

export 'robot_control.pb.dart';

/// Robot Control Service - replaces WebSocket for reliable communication
@$pb.GrpcServiceName('robotcontrol.RobotControl')
class RobotControlClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  RobotControlClient(super.channel, {super.options, super.interceptors});

  /// Bidirectional streaming for real-time updates and commands
  $grpc.ResponseStream<$0.ServerMessage> controlStream(
    $async.Stream<$0.ClientMessage> request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$controlStream, request, options: options);
  }

  /// Unary RPC for simple commands
  $grpc.ResponseFuture<$0.CommandResponse> sendCommand(
    $0.Command request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$sendCommand, request, options: options);
  }

  /// Server-streaming for heartbeat/status updates
  $grpc.ResponseStream<$0.Heartbeat> streamHeartbeat(
    $0.HeartbeatRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$streamHeartbeat, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$controlStream =
      $grpc.ClientMethod<$0.ClientMessage, $0.ServerMessage>(
          '/robotcontrol.RobotControl/ControlStream',
          ($0.ClientMessage value) => value.writeToBuffer(),
          $0.ServerMessage.fromBuffer);
  static final _$sendCommand =
      $grpc.ClientMethod<$0.Command, $0.CommandResponse>(
          '/robotcontrol.RobotControl/SendCommand',
          ($0.Command value) => value.writeToBuffer(),
          $0.CommandResponse.fromBuffer);
  static final _$streamHeartbeat =
      $grpc.ClientMethod<$0.HeartbeatRequest, $0.Heartbeat>(
          '/robotcontrol.RobotControl/StreamHeartbeat',
          ($0.HeartbeatRequest value) => value.writeToBuffer(),
          $0.Heartbeat.fromBuffer);
}

@$pb.GrpcServiceName('robotcontrol.RobotControl')
abstract class RobotControlServiceBase extends $grpc.Service {
  $core.String get $name => 'robotcontrol.RobotControl';

  RobotControlServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.ClientMessage, $0.ServerMessage>(
        'ControlStream',
        controlStream,
        true,
        true,
        ($core.List<$core.int> value) => $0.ClientMessage.fromBuffer(value),
        ($0.ServerMessage value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Command, $0.CommandResponse>(
        'SendCommand',
        sendCommand_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Command.fromBuffer(value),
        ($0.CommandResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.HeartbeatRequest, $0.Heartbeat>(
        'StreamHeartbeat',
        streamHeartbeat_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.HeartbeatRequest.fromBuffer(value),
        ($0.Heartbeat value) => value.writeToBuffer()));
  }

  $async.Stream<$0.ServerMessage> controlStream(
      $grpc.ServiceCall call, $async.Stream<$0.ClientMessage> request);

  $async.Future<$0.CommandResponse> sendCommand_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Command> $request) async {
    return sendCommand($call, await $request);
  }

  $async.Future<$0.CommandResponse> sendCommand(
      $grpc.ServiceCall call, $0.Command request);

  $async.Stream<$0.Heartbeat> streamHeartbeat_Pre($grpc.ServiceCall $call,
      $async.Future<$0.HeartbeatRequest> $request) async* {
    yield* streamHeartbeat($call, await $request);
  }

  $async.Stream<$0.Heartbeat> streamHeartbeat(
      $grpc.ServiceCall call, $0.HeartbeatRequest request);
}
