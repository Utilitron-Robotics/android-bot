// This is a generated file - do not edit.
//
// Generated from robot_control.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use clientMessageDescriptor instead')
const ClientMessage$json = {
  '1': 'ClientMessage',
  '2': [
    {
      '1': 'command',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.Command',
      '9': 0,
      '10': 'command'
    },
    {
      '1': 'heartbeat_request',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.HeartbeatRequest',
      '9': 0,
      '10': 'heartbeatRequest'
    },
    {
      '1': 'buffer_control',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.BufferControl',
      '9': 0,
      '10': 'bufferControl'
    },
  ],
  '8': [
    {'1': 'message'},
  ],
};

/// Descriptor for `ClientMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clientMessageDescriptor = $convert.base64Decode(
    'Cg1DbGllbnRNZXNzYWdlEjEKB2NvbW1hbmQYASABKAsyFS5yb2JvdGNvbnRyb2wuQ29tbWFuZE'
    'gAUgdjb21tYW5kEk0KEWhlYXJ0YmVhdF9yZXF1ZXN0GAIgASgLMh4ucm9ib3Rjb250cm9sLkhl'
    'YXJ0YmVhdFJlcXVlc3RIAFIQaGVhcnRiZWF0UmVxdWVzdBJECg5idWZmZXJfY29udHJvbBgDIA'
    'EoCzIbLnJvYm90Y29udHJvbC5CdWZmZXJDb250cm9sSABSDWJ1ZmZlckNvbnRyb2xCCQoHbWVz'
    'c2FnZQ==');

@$core.Deprecated('Use serverMessageDescriptor instead')
const ServerMessage$json = {
  '1': 'ServerMessage',
  '2': [
    {
      '1': 'heartbeat',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.Heartbeat',
      '9': 0,
      '10': 'heartbeat'
    },
    {
      '1': 'command_result',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.CommandResult',
      '9': 0,
      '10': 'commandResult'
    },
    {
      '1': 'robot_status',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.RobotStatus',
      '9': 0,
      '10': 'robotStatus'
    },
    {
      '1': 'buffer_state',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.BufferState',
      '9': 0,
      '10': 'bufferState'
    },
  ],
  '8': [
    {'1': 'message'},
  ],
};

/// Descriptor for `ServerMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serverMessageDescriptor = $convert.base64Decode(
    'Cg1TZXJ2ZXJNZXNzYWdlEjcKCWhlYXJ0YmVhdBgBIAEoCzIXLnJvYm90Y29udHJvbC5IZWFydG'
    'JlYXRIAFIJaGVhcnRiZWF0EkQKDmNvbW1hbmRfcmVzdWx0GAIgASgLMhsucm9ib3Rjb250cm9s'
    'LkNvbW1hbmRSZXN1bHRIAFINY29tbWFuZFJlc3VsdBI+Cgxyb2JvdF9zdGF0dXMYAyABKAsyGS'
    '5yb2JvdGNvbnRyb2wuUm9ib3RTdGF0dXNIAFILcm9ib3RTdGF0dXMSPgoMYnVmZmVyX3N0YXRl'
    'GAQgASgLMhkucm9ib3Rjb250cm9sLkJ1ZmZlclN0YXRlSABSC2J1ZmZlclN0YXRlQgkKB21lc3'
    'NhZ2U=');

@$core.Deprecated('Use commandDescriptor instead')
const Command$json = {
  '1': 'Command',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'type', '3': 2, '4': 1, '5': 9, '10': 'type'},
    {
      '1': 'data',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.robotcontrol.Command.DataEntry',
      '10': 'data'
    },
  ],
  '3': [Command_DataEntry$json],
};

@$core.Deprecated('Use commandDescriptor instead')
const Command_DataEntry$json = {
  '1': 'DataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `Command`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandDescriptor = $convert.base64Decode(
    'CgdDb21tYW5kEg4KAmlkGAEgASgJUgJpZBISCgR0eXBlGAIgASgJUgR0eXBlEjMKBGRhdGEYAy'
    'ADKAsyHy5yb2JvdGNvbnRyb2wuQ29tbWFuZC5EYXRhRW50cnlSBGRhdGEaNwoJRGF0YUVudHJ5'
    'EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbHVlGAIgASgJUgV2YWx1ZToCOAE=');

@$core.Deprecated('Use commandResponseDescriptor instead')
const CommandResponse$json = {
  '1': 'CommandResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {'1': 'command_id', '3': 3, '4': 1, '5': 9, '10': 'commandId'},
  ],
};

/// Descriptor for `CommandResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandResponseDescriptor = $convert.base64Decode(
    'Cg9Db21tYW5kUmVzcG9uc2USGAoHc3VjY2VzcxgBIAEoCFIHc3VjY2VzcxIYCgdtZXNzYWdlGA'
    'IgASgJUgdtZXNzYWdlEh0KCmNvbW1hbmRfaWQYAyABKAlSCWNvbW1hbmRJZA==');

@$core.Deprecated('Use commandResultDescriptor instead')
const CommandResult$json = {
  '1': 'CommandResult',
  '2': [
    {'1': 'command_id', '3': 1, '4': 1, '5': 9, '10': 'commandId'},
    {'1': 'status', '3': 2, '4': 1, '5': 9, '10': 'status'},
    {'1': 'message', '3': 3, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `CommandResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandResultDescriptor = $convert.base64Decode(
    'Cg1Db21tYW5kUmVzdWx0Eh0KCmNvbW1hbmRfaWQYASABKAlSCWNvbW1hbmRJZBIWCgZzdGF0dX'
    'MYAiABKAlSBnN0YXR1cxIYCgdtZXNzYWdlGAMgASgJUgdtZXNzYWdl');

@$core.Deprecated('Use heartbeatDescriptor instead')
const Heartbeat$json = {
  '1': 'Heartbeat',
  '2': [
    {'1': 'timestamp', '3': 1, '4': 1, '5': 3, '10': 'timestamp'},
    {
      '1': 'robot',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.RobotStatus',
      '10': 'robot'
    },
    {
      '1': 'buffer',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.BufferState',
      '10': 'buffer'
    },
    {
      '1': 'crowd_config',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.CrowdConfig',
      '10': 'crowdConfig'
    },
  ],
};

/// Descriptor for `Heartbeat`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List heartbeatDescriptor = $convert.base64Decode(
    'CglIZWFydGJlYXQSHAoJdGltZXN0YW1wGAEgASgDUgl0aW1lc3RhbXASLwoFcm9ib3QYAiABKA'
    'syGS5yb2JvdGNvbnRyb2wuUm9ib3RTdGF0dXNSBXJvYm90EjEKBmJ1ZmZlchgDIAEoCzIZLnJv'
    'Ym90Y29udHJvbC5CdWZmZXJTdGF0ZVIGYnVmZmVyEjwKDGNyb3dkX2NvbmZpZxgEIAEoCzIZLn'
    'JvYm90Y29udHJvbC5Dcm93ZENvbmZpZ1ILY3Jvd2RDb25maWc=');

@$core.Deprecated('Use heartbeatRequestDescriptor instead')
const HeartbeatRequest$json = {
  '1': 'HeartbeatRequest',
};

/// Descriptor for `HeartbeatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List heartbeatRequestDescriptor =
    $convert.base64Decode('ChBIZWFydGJlYXRSZXF1ZXN0');

@$core.Deprecated('Use robotStatusDescriptor instead')
const RobotStatus$json = {
  '1': 'RobotStatus',
  '2': [
    {'1': 'connected', '3': 1, '4': 1, '5': 8, '10': 'connected'},
    {'1': 'nav_status', '3': 2, '4': 1, '5': 5, '10': 'navStatus'},
    {'1': 'nav_goal', '3': 3, '4': 1, '5': 9, '10': 'navGoal'},
    {'1': 'battery', '3': 4, '4': 1, '5': 5, '10': 'battery'},
    {'1': 'safety_zone', '3': 5, '4': 1, '5': 9, '10': 'safetyZone'},
    {
      '1': 'pose',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.Pose2D',
      '10': 'pose'
    },
    {'1': 'linear_velocity', '3': 7, '4': 1, '5': 1, '10': 'linearVelocity'},
    {'1': 'angular_velocity', '3': 8, '4': 1, '5': 1, '10': 'angularVelocity'},
  ],
};

/// Descriptor for `RobotStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List robotStatusDescriptor = $convert.base64Decode(
    'CgtSb2JvdFN0YXR1cxIcCgljb25uZWN0ZWQYASABKAhSCWNvbm5lY3RlZBIdCgpuYXZfc3RhdH'
    'VzGAIgASgFUgluYXZTdGF0dXMSGQoIbmF2X2dvYWwYAyABKAlSB25hdkdvYWwSGAoHYmF0dGVy'
    'eRgEIAEoBVIHYmF0dGVyeRIfCgtzYWZldHlfem9uZRgFIAEoCVIKc2FmZXR5Wm9uZRIoCgRwb3'
    'NlGAYgASgLMhQucm9ib3Rjb250cm9sLlBvc2UyRFIEcG9zZRInCg9saW5lYXJfdmVsb2NpdHkY'
    'ByABKAFSDmxpbmVhclZlbG9jaXR5EikKEGFuZ3VsYXJfdmVsb2NpdHkYCCABKAFSD2FuZ3VsYX'
    'JWZWxvY2l0eQ==');

@$core.Deprecated('Use pose2DDescriptor instead')
const Pose2D$json = {
  '1': 'Pose2D',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 1, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 1, '10': 'y'},
    {'1': 'theta', '3': 3, '4': 1, '5': 1, '10': 'theta'},
  ],
};

/// Descriptor for `Pose2D`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pose2DDescriptor = $convert.base64Decode(
    'CgZQb3NlMkQSDAoBeBgBIAEoAVIBeBIMCgF5GAIgASgBUgF5EhQKBXRoZXRhGAMgASgBUgV0aG'
    'V0YQ==');

@$core.Deprecated('Use bufferStateDescriptor instead')
const BufferState$json = {
  '1': 'BufferState',
  '2': [
    {'1': 'paused', '3': 1, '4': 1, '5': 8, '10': 'paused'},
    {
      '1': 'current',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.BufferCommand',
      '10': 'current'
    },
    {'1': 'pending_count', '3': 3, '4': 1, '5': 5, '10': 'pendingCount'},
    {'1': 'completed_count', '3': 4, '4': 1, '5': 5, '10': 'completedCount'},
  ],
};

/// Descriptor for `BufferState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bufferStateDescriptor = $convert.base64Decode(
    'CgtCdWZmZXJTdGF0ZRIWCgZwYXVzZWQYASABKAhSBnBhdXNlZBI1CgdjdXJyZW50GAIgASgLMh'
    'sucm9ib3Rjb250cm9sLkJ1ZmZlckNvbW1hbmRSB2N1cnJlbnQSIwoNcGVuZGluZ19jb3VudBgD'
    'IAEoBVIMcGVuZGluZ0NvdW50EicKD2NvbXBsZXRlZF9jb3VudBgEIAEoBVIOY29tcGxldGVkQ2'
    '91bnQ=');

@$core.Deprecated('Use bufferCommandDescriptor instead')
const BufferCommand$json = {
  '1': 'BufferCommand',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'type', '3': 2, '4': 1, '5': 9, '10': 'type'},
    {'1': 'started_at', '3': 3, '4': 1, '5': 3, '10': 'startedAt'},
    {'1': 'elapsed_ms', '3': 4, '4': 1, '5': 3, '10': 'elapsedMs'},
    {
      '1': 'data',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.robotcontrol.BufferCommand.DataEntry',
      '10': 'data'
    },
  ],
  '3': [BufferCommand_DataEntry$json],
};

@$core.Deprecated('Use bufferCommandDescriptor instead')
const BufferCommand_DataEntry$json = {
  '1': 'DataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `BufferCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bufferCommandDescriptor = $convert.base64Decode(
    'Cg1CdWZmZXJDb21tYW5kEg4KAmlkGAEgASgJUgJpZBISCgR0eXBlGAIgASgJUgR0eXBlEh0KCn'
    'N0YXJ0ZWRfYXQYAyABKANSCXN0YXJ0ZWRBdBIdCgplbGFwc2VkX21zGAQgASgDUgllbGFwc2Vk'
    'TXMSOQoEZGF0YRgFIAMoCzIlLnJvYm90Y29udHJvbC5CdWZmZXJDb21tYW5kLkRhdGFFbnRyeV'
    'IEZGF0YRo3CglEYXRhRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZh'
    'bHVlOgI4AQ==');

@$core.Deprecated('Use bufferControlDescriptor instead')
const BufferControl$json = {
  '1': 'BufferControl',
  '2': [
    {
      '1': 'load',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.LoadCommands',
      '9': 0,
      '10': 'load'
    },
    {'1': 'pause', '3': 2, '4': 1, '5': 8, '9': 0, '10': 'pause'},
    {'1': 'resume', '3': 3, '4': 1, '5': 8, '9': 0, '10': 'resume'},
    {'1': 'skip', '3': 4, '4': 1, '5': 8, '9': 0, '10': 'skip'},
    {'1': 'clear', '3': 5, '4': 1, '5': 8, '9': 0, '10': 'clear'},
    {
      '1': 'trigger_start',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.robotcontrol.TriggerStartTour',
      '9': 0,
      '10': 'triggerStart'
    },
  ],
  '8': [
    {'1': 'control'},
  ],
};

/// Descriptor for `BufferControl`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bufferControlDescriptor = $convert.base64Decode(
    'Cg1CdWZmZXJDb250cm9sEjAKBGxvYWQYASABKAsyGi5yb2JvdGNvbnRyb2wuTG9hZENvbW1hbm'
    'RzSABSBGxvYWQSFgoFcGF1c2UYAiABKAhIAFIFcGF1c2USGAoGcmVzdW1lGAMgASgISABSBnJl'
    'c3VtZRIUCgRza2lwGAQgASgISABSBHNraXASFgoFY2xlYXIYBSABKAhIAFIFY2xlYXISRQoNdH'
    'JpZ2dlcl9zdGFydBgGIAEoCzIeLnJvYm90Y29udHJvbC5UcmlnZ2VyU3RhcnRUb3VySABSDHRy'
    'aWdnZXJTdGFydEIJCgdjb250cm9s');

@$core.Deprecated('Use loadCommandsDescriptor instead')
const LoadCommands$json = {
  '1': 'LoadCommands',
  '2': [
    {
      '1': 'commands',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.robotcontrol.BufferCommand',
      '10': 'commands'
    },
    {'1': 'clear_existing', '3': 2, '4': 1, '5': 8, '10': 'clearExisting'},
  ],
};

/// Descriptor for `LoadCommands`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loadCommandsDescriptor = $convert.base64Decode(
    'CgxMb2FkQ29tbWFuZHMSNwoIY29tbWFuZHMYASADKAsyGy5yb2JvdGNvbnRyb2wuQnVmZmVyQ2'
    '9tbWFuZFIIY29tbWFuZHMSJQoOY2xlYXJfZXhpc3RpbmcYAiABKAhSDWNsZWFyRXhpc3Rpbmc=');

@$core.Deprecated('Use triggerStartTourDescriptor instead')
const TriggerStartTour$json = {
  '1': 'TriggerStartTour',
  '2': [
    {'1': 'sequence_id', '3': 1, '4': 1, '5': 9, '10': 'sequenceId'},
  ],
};

/// Descriptor for `TriggerStartTour`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List triggerStartTourDescriptor = $convert.base64Decode(
    'ChBUcmlnZ2VyU3RhcnRUb3VyEh8KC3NlcXVlbmNlX2lkGAEgASgJUgpzZXF1ZW5jZUlk');

@$core.Deprecated('Use crowdConfigDescriptor instead')
const CrowdConfig$json = {
  '1': 'CrowdConfig',
  '2': [
    {
      '1': 'safe_distance_meters',
      '3': 1,
      '4': 1,
      '5': 1,
      '10': 'safeDistanceMeters'
    },
    {'1': 'ramp_rate', '3': 2, '4': 1, '5': 1, '10': 'rampRate'},
  ],
};

/// Descriptor for `CrowdConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List crowdConfigDescriptor = $convert.base64Decode(
    'CgtDcm93ZENvbmZpZxIwChRzYWZlX2Rpc3RhbmNlX21ldGVycxgBIAEoAVISc2FmZURpc3Rhbm'
    'NlTWV0ZXJzEhsKCXJhbXBfcmF0ZRgCIAEoAVIIcmFtcFJhdGU=');
