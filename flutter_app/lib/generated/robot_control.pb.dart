// This is a generated file - do not edit.
//
// Generated from robot_control.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

enum ClientMessage_Message { command, heartbeatRequest, bufferControl, notSet }

/// Client messages (Flutter → Relay)
class ClientMessage extends $pb.GeneratedMessage {
  factory ClientMessage({
    Command? command,
    HeartbeatRequest? heartbeatRequest,
    BufferControl? bufferControl,
  }) {
    final result = create();
    if (command != null) result.command = command;
    if (heartbeatRequest != null) result.heartbeatRequest = heartbeatRequest;
    if (bufferControl != null) result.bufferControl = bufferControl;
    return result;
  }

  ClientMessage._();

  factory ClientMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ClientMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ClientMessage_Message>
      _ClientMessage_MessageByTag = {
    1: ClientMessage_Message.command,
    2: ClientMessage_Message.heartbeatRequest,
    3: ClientMessage_Message.bufferControl,
    0: ClientMessage_Message.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClientMessage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3])
    ..aOM<Command>(1, _omitFieldNames ? '' : 'command',
        subBuilder: Command.create)
    ..aOM<HeartbeatRequest>(2, _omitFieldNames ? '' : 'heartbeatRequest',
        subBuilder: HeartbeatRequest.create)
    ..aOM<BufferControl>(3, _omitFieldNames ? '' : 'bufferControl',
        subBuilder: BufferControl.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientMessage copyWith(void Function(ClientMessage) updates) =>
      super.copyWith((message) => updates(message as ClientMessage))
          as ClientMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ClientMessage create() => ClientMessage._();
  @$core.override
  ClientMessage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ClientMessage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ClientMessage>(create);
  static ClientMessage? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  ClientMessage_Message whichMessage() =>
      _ClientMessage_MessageByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  void clearMessage() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  Command get command => $_getN(0);
  @$pb.TagNumber(1)
  set command(Command value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCommand() => $_has(0);
  @$pb.TagNumber(1)
  void clearCommand() => $_clearField(1);
  @$pb.TagNumber(1)
  Command ensureCommand() => $_ensure(0);

  @$pb.TagNumber(2)
  HeartbeatRequest get heartbeatRequest => $_getN(1);
  @$pb.TagNumber(2)
  set heartbeatRequest(HeartbeatRequest value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasHeartbeatRequest() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeartbeatRequest() => $_clearField(2);
  @$pb.TagNumber(2)
  HeartbeatRequest ensureHeartbeatRequest() => $_ensure(1);

  @$pb.TagNumber(3)
  BufferControl get bufferControl => $_getN(2);
  @$pb.TagNumber(3)
  set bufferControl(BufferControl value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasBufferControl() => $_has(2);
  @$pb.TagNumber(3)
  void clearBufferControl() => $_clearField(3);
  @$pb.TagNumber(3)
  BufferControl ensureBufferControl() => $_ensure(2);
}

enum ServerMessage_Message {
  heartbeat,
  commandResult,
  robotStatus,
  bufferState,
  notSet
}

/// Server messages (Relay → Flutter)
class ServerMessage extends $pb.GeneratedMessage {
  factory ServerMessage({
    Heartbeat? heartbeat,
    CommandResult? commandResult,
    RobotStatus? robotStatus,
    BufferState? bufferState,
  }) {
    final result = create();
    if (heartbeat != null) result.heartbeat = heartbeat;
    if (commandResult != null) result.commandResult = commandResult;
    if (robotStatus != null) result.robotStatus = robotStatus;
    if (bufferState != null) result.bufferState = bufferState;
    return result;
  }

  ServerMessage._();

  factory ServerMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ServerMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ServerMessage_Message>
      _ServerMessage_MessageByTag = {
    1: ServerMessage_Message.heartbeat,
    2: ServerMessage_Message.commandResult,
    3: ServerMessage_Message.robotStatus,
    4: ServerMessage_Message.bufferState,
    0: ServerMessage_Message.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ServerMessage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4])
    ..aOM<Heartbeat>(1, _omitFieldNames ? '' : 'heartbeat',
        subBuilder: Heartbeat.create)
    ..aOM<CommandResult>(2, _omitFieldNames ? '' : 'commandResult',
        subBuilder: CommandResult.create)
    ..aOM<RobotStatus>(3, _omitFieldNames ? '' : 'robotStatus',
        subBuilder: RobotStatus.create)
    ..aOM<BufferState>(4, _omitFieldNames ? '' : 'bufferState',
        subBuilder: BufferState.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerMessage copyWith(void Function(ServerMessage) updates) =>
      super.copyWith((message) => updates(message as ServerMessage))
          as ServerMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ServerMessage create() => ServerMessage._();
  @$core.override
  ServerMessage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ServerMessage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ServerMessage>(create);
  static ServerMessage? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  ServerMessage_Message whichMessage() =>
      _ServerMessage_MessageByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearMessage() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  Heartbeat get heartbeat => $_getN(0);
  @$pb.TagNumber(1)
  set heartbeat(Heartbeat value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasHeartbeat() => $_has(0);
  @$pb.TagNumber(1)
  void clearHeartbeat() => $_clearField(1);
  @$pb.TagNumber(1)
  Heartbeat ensureHeartbeat() => $_ensure(0);

  @$pb.TagNumber(2)
  CommandResult get commandResult => $_getN(1);
  @$pb.TagNumber(2)
  set commandResult(CommandResult value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCommandResult() => $_has(1);
  @$pb.TagNumber(2)
  void clearCommandResult() => $_clearField(2);
  @$pb.TagNumber(2)
  CommandResult ensureCommandResult() => $_ensure(1);

  @$pb.TagNumber(3)
  RobotStatus get robotStatus => $_getN(2);
  @$pb.TagNumber(3)
  set robotStatus(RobotStatus value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasRobotStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearRobotStatus() => $_clearField(3);
  @$pb.TagNumber(3)
  RobotStatus ensureRobotStatus() => $_ensure(2);

  @$pb.TagNumber(4)
  BufferState get bufferState => $_getN(3);
  @$pb.TagNumber(4)
  set bufferState(BufferState value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasBufferState() => $_has(3);
  @$pb.TagNumber(4)
  void clearBufferState() => $_clearField(4);
  @$pb.TagNumber(4)
  BufferState ensureBufferState() => $_ensure(3);
}

/// Command from Flutter to relay/robot
class Command extends $pb.GeneratedMessage {
  factory Command({
    $core.String? id,
    $core.String? type,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? data,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (type != null) result.type = type;
    if (data != null) result.data.addEntries(data);
    return result;
  }

  Command._();

  factory Command.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Command.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Command',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'type')
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'data',
        entryClassName: 'Command.DataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('robotcontrol'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Command clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Command copyWith(void Function(Command) updates) =>
      super.copyWith((message) => updates(message as Command)) as Command;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Command create() => Command._();
  @$core.override
  Command createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Command getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Command>(create);
  static Command? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get type => $_getSZ(1);
  @$pb.TagNumber(2)
  set type($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbMap<$core.String, $core.String> get data => $_getMap(2);
}

class CommandResponse extends $pb.GeneratedMessage {
  factory CommandResponse({
    $core.bool? success,
    $core.String? message,
    $core.String? commandId,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (message != null) result.message = message;
    if (commandId != null) result.commandId = commandId;
    return result;
  }

  CommandResponse._();

  factory CommandResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CommandResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommandResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..aOS(3, _omitFieldNames ? '' : 'commandId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandResponse copyWith(void Function(CommandResponse) updates) =>
      super.copyWith((message) => updates(message as CommandResponse))
          as CommandResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CommandResponse create() => CommandResponse._();
  @$core.override
  CommandResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CommandResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CommandResponse>(create);
  static CommandResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get commandId => $_getSZ(2);
  @$pb.TagNumber(3)
  set commandId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCommandId() => $_has(2);
  @$pb.TagNumber(3)
  void clearCommandId() => $_clearField(3);
}

class CommandResult extends $pb.GeneratedMessage {
  factory CommandResult({
    $core.String? commandId,
    $core.String? status,
    $core.String? message,
  }) {
    final result = create();
    if (commandId != null) result.commandId = commandId;
    if (status != null) result.status = status;
    if (message != null) result.message = message;
    return result;
  }

  CommandResult._();

  factory CommandResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CommandResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommandResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'commandId')
    ..aOS(2, _omitFieldNames ? '' : 'status')
    ..aOS(3, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandResult copyWith(void Function(CommandResult) updates) =>
      super.copyWith((message) => updates(message as CommandResult))
          as CommandResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CommandResult create() => CommandResult._();
  @$core.override
  CommandResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CommandResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CommandResult>(create);
  static CommandResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get commandId => $_getSZ(0);
  @$pb.TagNumber(1)
  set commandId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCommandId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCommandId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get status => $_getSZ(1);
  @$pb.TagNumber(2)
  set status($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get message => $_getSZ(2);
  @$pb.TagNumber(3)
  set message($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessage() => $_clearField(3);
}

/// Heartbeat with full system state
class Heartbeat extends $pb.GeneratedMessage {
  factory Heartbeat({
    $fixnum.Int64? timestamp,
    RobotStatus? robot,
    BufferState? buffer,
    CrowdConfig? crowdConfig,
  }) {
    final result = create();
    if (timestamp != null) result.timestamp = timestamp;
    if (robot != null) result.robot = robot;
    if (buffer != null) result.buffer = buffer;
    if (crowdConfig != null) result.crowdConfig = crowdConfig;
    return result;
  }

  Heartbeat._();

  factory Heartbeat.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Heartbeat.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Heartbeat',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'timestamp')
    ..aOM<RobotStatus>(2, _omitFieldNames ? '' : 'robot',
        subBuilder: RobotStatus.create)
    ..aOM<BufferState>(3, _omitFieldNames ? '' : 'buffer',
        subBuilder: BufferState.create)
    ..aOM<CrowdConfig>(4, _omitFieldNames ? '' : 'crowdConfig',
        subBuilder: CrowdConfig.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Heartbeat clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Heartbeat copyWith(void Function(Heartbeat) updates) =>
      super.copyWith((message) => updates(message as Heartbeat)) as Heartbeat;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Heartbeat create() => Heartbeat._();
  @$core.override
  Heartbeat createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Heartbeat getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Heartbeat>(create);
  static Heartbeat? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get timestamp => $_getI64(0);
  @$pb.TagNumber(1)
  set timestamp($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTimestamp() => $_has(0);
  @$pb.TagNumber(1)
  void clearTimestamp() => $_clearField(1);

  @$pb.TagNumber(2)
  RobotStatus get robot => $_getN(1);
  @$pb.TagNumber(2)
  set robot(RobotStatus value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRobot() => $_has(1);
  @$pb.TagNumber(2)
  void clearRobot() => $_clearField(2);
  @$pb.TagNumber(2)
  RobotStatus ensureRobot() => $_ensure(1);

  @$pb.TagNumber(3)
  BufferState get buffer => $_getN(2);
  @$pb.TagNumber(3)
  set buffer(BufferState value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasBuffer() => $_has(2);
  @$pb.TagNumber(3)
  void clearBuffer() => $_clearField(3);
  @$pb.TagNumber(3)
  BufferState ensureBuffer() => $_ensure(2);

  @$pb.TagNumber(4)
  CrowdConfig get crowdConfig => $_getN(3);
  @$pb.TagNumber(4)
  set crowdConfig(CrowdConfig value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasCrowdConfig() => $_has(3);
  @$pb.TagNumber(4)
  void clearCrowdConfig() => $_clearField(4);
  @$pb.TagNumber(4)
  CrowdConfig ensureCrowdConfig() => $_ensure(3);
}

class HeartbeatRequest extends $pb.GeneratedMessage {
  factory HeartbeatRequest() => create();

  HeartbeatRequest._();

  factory HeartbeatRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HeartbeatRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HeartbeatRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HeartbeatRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HeartbeatRequest copyWith(void Function(HeartbeatRequest) updates) =>
      super.copyWith((message) => updates(message as HeartbeatRequest))
          as HeartbeatRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HeartbeatRequest create() => HeartbeatRequest._();
  @$core.override
  HeartbeatRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HeartbeatRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HeartbeatRequest>(create);
  static HeartbeatRequest? _defaultInstance;
}

/// Robot status
class RobotStatus extends $pb.GeneratedMessage {
  factory RobotStatus({
    $core.bool? connected,
    $core.int? navStatus,
    $core.String? navGoal,
    $core.int? battery,
    $core.String? safetyZone,
    Pose2D? pose,
    $core.double? linearVelocity,
    $core.double? angularVelocity,
  }) {
    final result = create();
    if (connected != null) result.connected = connected;
    if (navStatus != null) result.navStatus = navStatus;
    if (navGoal != null) result.navGoal = navGoal;
    if (battery != null) result.battery = battery;
    if (safetyZone != null) result.safetyZone = safetyZone;
    if (pose != null) result.pose = pose;
    if (linearVelocity != null) result.linearVelocity = linearVelocity;
    if (angularVelocity != null) result.angularVelocity = angularVelocity;
    return result;
  }

  RobotStatus._();

  factory RobotStatus.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RobotStatus.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RobotStatus',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'connected')
    ..aI(2, _omitFieldNames ? '' : 'navStatus')
    ..aOS(3, _omitFieldNames ? '' : 'navGoal')
    ..aI(4, _omitFieldNames ? '' : 'battery')
    ..aOS(5, _omitFieldNames ? '' : 'safetyZone')
    ..aOM<Pose2D>(6, _omitFieldNames ? '' : 'pose', subBuilder: Pose2D.create)
    ..aD(7, _omitFieldNames ? '' : 'linearVelocity')
    ..aD(8, _omitFieldNames ? '' : 'angularVelocity')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RobotStatus clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RobotStatus copyWith(void Function(RobotStatus) updates) =>
      super.copyWith((message) => updates(message as RobotStatus))
          as RobotStatus;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RobotStatus create() => RobotStatus._();
  @$core.override
  RobotStatus createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RobotStatus getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RobotStatus>(create);
  static RobotStatus? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get connected => $_getBF(0);
  @$pb.TagNumber(1)
  set connected($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConnected() => $_has(0);
  @$pb.TagNumber(1)
  void clearConnected() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get navStatus => $_getIZ(1);
  @$pb.TagNumber(2)
  set navStatus($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNavStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearNavStatus() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get navGoal => $_getSZ(2);
  @$pb.TagNumber(3)
  set navGoal($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNavGoal() => $_has(2);
  @$pb.TagNumber(3)
  void clearNavGoal() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get battery => $_getIZ(3);
  @$pb.TagNumber(4)
  set battery($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBattery() => $_has(3);
  @$pb.TagNumber(4)
  void clearBattery() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get safetyZone => $_getSZ(4);
  @$pb.TagNumber(5)
  set safetyZone($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSafetyZone() => $_has(4);
  @$pb.TagNumber(5)
  void clearSafetyZone() => $_clearField(5);

  @$pb.TagNumber(6)
  Pose2D get pose => $_getN(5);
  @$pb.TagNumber(6)
  set pose(Pose2D value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasPose() => $_has(5);
  @$pb.TagNumber(6)
  void clearPose() => $_clearField(6);
  @$pb.TagNumber(6)
  Pose2D ensurePose() => $_ensure(5);

  @$pb.TagNumber(7)
  $core.double get linearVelocity => $_getN(6);
  @$pb.TagNumber(7)
  set linearVelocity($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLinearVelocity() => $_has(6);
  @$pb.TagNumber(7)
  void clearLinearVelocity() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get angularVelocity => $_getN(7);
  @$pb.TagNumber(8)
  set angularVelocity($core.double value) => $_setDouble(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAngularVelocity() => $_has(7);
  @$pb.TagNumber(8)
  void clearAngularVelocity() => $_clearField(8);
}

class Pose2D extends $pb.GeneratedMessage {
  factory Pose2D({
    $core.double? x,
    $core.double? y,
    $core.double? theta,
  }) {
    final result = create();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (theta != null) result.theta = theta;
    return result;
  }

  Pose2D._();

  factory Pose2D.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Pose2D.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Pose2D',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'x')
    ..aD(2, _omitFieldNames ? '' : 'y')
    ..aD(3, _omitFieldNames ? '' : 'theta')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pose2D clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pose2D copyWith(void Function(Pose2D) updates) =>
      super.copyWith((message) => updates(message as Pose2D)) as Pose2D;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Pose2D create() => Pose2D._();
  @$core.override
  Pose2D createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Pose2D getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Pose2D>(create);
  static Pose2D? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get x => $_getN(0);
  @$pb.TagNumber(1)
  set x($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasX() => $_has(0);
  @$pb.TagNumber(1)
  void clearX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get y => $_getN(1);
  @$pb.TagNumber(2)
  set y($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasY() => $_has(1);
  @$pb.TagNumber(2)
  void clearY() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get theta => $_getN(2);
  @$pb.TagNumber(3)
  set theta($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTheta() => $_has(2);
  @$pb.TagNumber(3)
  void clearTheta() => $_clearField(3);
}

/// Buffer state
class BufferState extends $pb.GeneratedMessage {
  factory BufferState({
    $core.bool? paused,
    BufferCommand? current,
    $core.int? pendingCount,
    $core.int? completedCount,
  }) {
    final result = create();
    if (paused != null) result.paused = paused;
    if (current != null) result.current = current;
    if (pendingCount != null) result.pendingCount = pendingCount;
    if (completedCount != null) result.completedCount = completedCount;
    return result;
  }

  BufferState._();

  factory BufferState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BufferState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BufferState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'paused')
    ..aOM<BufferCommand>(2, _omitFieldNames ? '' : 'current',
        subBuilder: BufferCommand.create)
    ..aI(3, _omitFieldNames ? '' : 'pendingCount')
    ..aI(4, _omitFieldNames ? '' : 'completedCount')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BufferState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BufferState copyWith(void Function(BufferState) updates) =>
      super.copyWith((message) => updates(message as BufferState))
          as BufferState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BufferState create() => BufferState._();
  @$core.override
  BufferState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BufferState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BufferState>(create);
  static BufferState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get paused => $_getBF(0);
  @$pb.TagNumber(1)
  set paused($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPaused() => $_has(0);
  @$pb.TagNumber(1)
  void clearPaused() => $_clearField(1);

  @$pb.TagNumber(2)
  BufferCommand get current => $_getN(1);
  @$pb.TagNumber(2)
  set current(BufferCommand value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrent() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrent() => $_clearField(2);
  @$pb.TagNumber(2)
  BufferCommand ensureCurrent() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.int get pendingCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set pendingCount($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPendingCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearPendingCount() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get completedCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set completedCount($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCompletedCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearCompletedCount() => $_clearField(4);
}

class BufferCommand extends $pb.GeneratedMessage {
  factory BufferCommand({
    $core.String? id,
    $core.String? type,
    $fixnum.Int64? startedAt,
    $fixnum.Int64? elapsedMs,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? data,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (type != null) result.type = type;
    if (startedAt != null) result.startedAt = startedAt;
    if (elapsedMs != null) result.elapsedMs = elapsedMs;
    if (data != null) result.data.addEntries(data);
    return result;
  }

  BufferCommand._();

  factory BufferCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BufferCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BufferCommand',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'type')
    ..aInt64(3, _omitFieldNames ? '' : 'startedAt')
    ..aInt64(4, _omitFieldNames ? '' : 'elapsedMs')
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'data',
        entryClassName: 'BufferCommand.DataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('robotcontrol'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BufferCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BufferCommand copyWith(void Function(BufferCommand) updates) =>
      super.copyWith((message) => updates(message as BufferCommand))
          as BufferCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BufferCommand create() => BufferCommand._();
  @$core.override
  BufferCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BufferCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BufferCommand>(create);
  static BufferCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get type => $_getSZ(1);
  @$pb.TagNumber(2)
  set type($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get startedAt => $_getI64(2);
  @$pb.TagNumber(3)
  set startedAt($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStartedAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearStartedAt() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get elapsedMs => $_getI64(3);
  @$pb.TagNumber(4)
  set elapsedMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasElapsedMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearElapsedMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbMap<$core.String, $core.String> get data => $_getMap(4);
}

enum BufferControl_Control {
  load,
  pause,
  resume,
  skip,
  clear_5,
  triggerStart,
  notSet
}

/// Buffer control commands
class BufferControl extends $pb.GeneratedMessage {
  factory BufferControl({
    LoadCommands? load,
    $core.bool? pause,
    $core.bool? resume,
    $core.bool? skip,
    $core.bool? clear_5,
    TriggerStartTour? triggerStart,
  }) {
    final result = create();
    if (load != null) result.load = load;
    if (pause != null) result.pause = pause;
    if (resume != null) result.resume = resume;
    if (skip != null) result.skip = skip;
    if (clear_5 != null) result.clear_5 = clear_5;
    if (triggerStart != null) result.triggerStart = triggerStart;
    return result;
  }

  BufferControl._();

  factory BufferControl.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BufferControl.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, BufferControl_Control>
      _BufferControl_ControlByTag = {
    1: BufferControl_Control.load,
    2: BufferControl_Control.pause,
    3: BufferControl_Control.resume,
    4: BufferControl_Control.skip,
    5: BufferControl_Control.clear_5,
    6: BufferControl_Control.triggerStart,
    0: BufferControl_Control.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BufferControl',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 5, 6])
    ..aOM<LoadCommands>(1, _omitFieldNames ? '' : 'load',
        subBuilder: LoadCommands.create)
    ..aOB(2, _omitFieldNames ? '' : 'pause')
    ..aOB(3, _omitFieldNames ? '' : 'resume')
    ..aOB(4, _omitFieldNames ? '' : 'skip')
    ..aOB(5, _omitFieldNames ? '' : 'clear')
    ..aOM<TriggerStartTour>(6, _omitFieldNames ? '' : 'triggerStart',
        subBuilder: TriggerStartTour.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BufferControl clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BufferControl copyWith(void Function(BufferControl) updates) =>
      super.copyWith((message) => updates(message as BufferControl))
          as BufferControl;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BufferControl create() => BufferControl._();
  @$core.override
  BufferControl createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BufferControl getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BufferControl>(create);
  static BufferControl? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  BufferControl_Control whichControl() =>
      _BufferControl_ControlByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  void clearControl() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  LoadCommands get load => $_getN(0);
  @$pb.TagNumber(1)
  set load(LoadCommands value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasLoad() => $_has(0);
  @$pb.TagNumber(1)
  void clearLoad() => $_clearField(1);
  @$pb.TagNumber(1)
  LoadCommands ensureLoad() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.bool get pause => $_getBF(1);
  @$pb.TagNumber(2)
  set pause($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPause() => $_has(1);
  @$pb.TagNumber(2)
  void clearPause() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get resume => $_getBF(2);
  @$pb.TagNumber(3)
  set resume($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasResume() => $_has(2);
  @$pb.TagNumber(3)
  void clearResume() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get skip => $_getBF(3);
  @$pb.TagNumber(4)
  set skip($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSkip() => $_has(3);
  @$pb.TagNumber(4)
  void clearSkip() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get clear_5 => $_getBF(4);
  @$pb.TagNumber(5)
  set clear_5($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasClear_5() => $_has(4);
  @$pb.TagNumber(5)
  void clearClear_5() => $_clearField(5);

  @$pb.TagNumber(6)
  TriggerStartTour get triggerStart => $_getN(5);
  @$pb.TagNumber(6)
  set triggerStart(TriggerStartTour value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasTriggerStart() => $_has(5);
  @$pb.TagNumber(6)
  void clearTriggerStart() => $_clearField(6);
  @$pb.TagNumber(6)
  TriggerStartTour ensureTriggerStart() => $_ensure(5);
}

class LoadCommands extends $pb.GeneratedMessage {
  factory LoadCommands({
    $core.Iterable<BufferCommand>? commands,
    $core.bool? clearExisting,
  }) {
    final result = create();
    if (commands != null) result.commands.addAll(commands);
    if (clearExisting != null) result.clearExisting = clearExisting;
    return result;
  }

  LoadCommands._();

  factory LoadCommands.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoadCommands.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoadCommands',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..pPM<BufferCommand>(1, _omitFieldNames ? '' : 'commands',
        subBuilder: BufferCommand.create)
    ..aOB(2, _omitFieldNames ? '' : 'clearExisting')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoadCommands clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoadCommands copyWith(void Function(LoadCommands) updates) =>
      super.copyWith((message) => updates(message as LoadCommands))
          as LoadCommands;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoadCommands create() => LoadCommands._();
  @$core.override
  LoadCommands createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoadCommands getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoadCommands>(create);
  static LoadCommands? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<BufferCommand> get commands => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get clearExisting => $_getBF(1);
  @$pb.TagNumber(2)
  set clearExisting($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasClearExisting() => $_has(1);
  @$pb.TagNumber(2)
  void clearClearExisting() => $_clearField(2);
}

/// UI Control - trigger actions on tablet
class TriggerStartTour extends $pb.GeneratedMessage {
  factory TriggerStartTour({
    $core.String? sequenceId,
  }) {
    final result = create();
    if (sequenceId != null) result.sequenceId = sequenceId;
    return result;
  }

  TriggerStartTour._();

  factory TriggerStartTour.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TriggerStartTour.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TriggerStartTour',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sequenceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TriggerStartTour clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TriggerStartTour copyWith(void Function(TriggerStartTour) updates) =>
      super.copyWith((message) => updates(message as TriggerStartTour))
          as TriggerStartTour;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TriggerStartTour create() => TriggerStartTour._();
  @$core.override
  TriggerStartTour createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TriggerStartTour getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TriggerStartTour>(create);
  static TriggerStartTour? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sequenceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sequenceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSequenceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSequenceId() => $_clearField(1);
}

/// Crowd logic config
class CrowdConfig extends $pb.GeneratedMessage {
  factory CrowdConfig({
    $core.double? safeDistanceMeters,
    $core.double? rampRate,
  }) {
    final result = create();
    if (safeDistanceMeters != null)
      result.safeDistanceMeters = safeDistanceMeters;
    if (rampRate != null) result.rampRate = rampRate;
    return result;
  }

  CrowdConfig._();

  factory CrowdConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CrowdConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CrowdConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'robotcontrol'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'safeDistanceMeters')
    ..aD(2, _omitFieldNames ? '' : 'rampRate')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CrowdConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CrowdConfig copyWith(void Function(CrowdConfig) updates) =>
      super.copyWith((message) => updates(message as CrowdConfig))
          as CrowdConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CrowdConfig create() => CrowdConfig._();
  @$core.override
  CrowdConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CrowdConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CrowdConfig>(create);
  static CrowdConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get safeDistanceMeters => $_getN(0);
  @$pb.TagNumber(1)
  set safeDistanceMeters($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSafeDistanceMeters() => $_has(0);
  @$pb.TagNumber(1)
  void clearSafeDistanceMeters() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get rampRate => $_getN(1);
  @$pb.TagNumber(2)
  set rampRate($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRampRate() => $_has(1);
  @$pb.TagNumber(2)
  void clearRampRate() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
