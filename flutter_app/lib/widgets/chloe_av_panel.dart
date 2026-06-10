import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

/// Chloe's eyes and ears in the HUD.
///
/// Renders the Nano's MJPEG stream (OAK-D, encoded on-camera) and toggles
/// her mic audio (endless WAV over HTTP). URLs arrive via the synthetic
/// `/chloe/av` topic; this widget only mounts when an endpoint is live, and
/// tears everything down on dispose — no zombie streams.
class ChloeAvPanel extends StatefulWidget {
  final String? videoUrl;
  final String? audioUrl;
  final String? baseUrl;
  final bool cameraUp;
  final VoidCallback? onClose;

  const ChloeAvPanel({
    super.key,
    required this.videoUrl,
    required this.audioUrl,
    this.baseUrl,
    required this.cameraUp,
    this.onClose,
  });

  @override
  State<ChloeAvPanel> createState() => _ChloeAvPanelState();
}

class _ChloeAvPanelState extends State<ChloeAvPanel> {
  AudioPlayer? _audioPlayer;
  bool _audioOn = false;
  bool _audioBusy = false;
  bool _wakeBusy = false;

  /// POST /wake or /sleep on the Nano. The Nano runs its env-configured
  /// command and reports honestly (501 when not configured).
  Future<void> _sendWakeSleep(String action) async {
    final base = widget.baseUrl;
    if (base == null || _wakeBusy) return;
    setState(() => _wakeBusy = true);
    String result;
    try {
      final res = await http
          .post(Uri.parse('$base/$action'))
          .timeout(const Duration(seconds: 35));
      if (res.statusCode == 200) {
        result = 'Chloe $action: OK';
      } else {
        final body = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
        result = 'Chloe $action failed (${res.statusCode}): $body';
      }
    } catch (e) {
      result = 'Chloe $action failed: $e';
    }
    if (mounted) {
      setState(() => _wakeBusy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result)));
    }
  }

  Future<void> _toggleAudio() async {
    final url = widget.audioUrl;
    if (url == null || _audioBusy) return;
    setState(() => _audioBusy = true);
    try {
      if (_audioOn) {
        await _audioPlayer?.stop();
        await _audioPlayer?.dispose();
        _audioPlayer = null;
        _audioOn = false;
      } else {
        final player = AudioPlayer();
        await player.setUrl(url);
        unawaited(player.play());
        _audioPlayer = player;
        _audioOn = true;
      }
    } catch (e) {
      debugPrint('ChloeAvPanel: audio failed: $e');
      await _audioPlayer?.dispose();
      _audioPlayer = null;
      _audioOn = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chloe audio failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00D4FF);
    return Container(
      width: 328,
      decoration: BoxDecoration(
        color: const Color(0xCC0A0E14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 2),
            child: Row(
              children: [
                const Icon(Icons.smart_toy, color: accent, size: 16),
                const SizedBox(width: 6),
                const Text('CHLOE',
                    style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 2)),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: 'Wake Chloe',
                  color: _wakeBusy ? Colors.grey : Colors.amber,
                  icon: const Icon(Icons.wb_sunny),
                  onPressed: widget.baseUrl == null || _wakeBusy
                      ? null
                      : () => _sendWakeSleep('wake'),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: 'Put Chloe to sleep (teleop mode)',
                  color: _wakeBusy ? Colors.grey : Colors.blueGrey,
                  icon: const Icon(Icons.bedtime),
                  onPressed: widget.baseUrl == null || _wakeBusy
                      ? null
                      : () => _sendWakeSleep('sleep'),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: _audioOn ? 'Mute her mic' : 'Hear her mic',
                  color: _audioOn ? Colors.greenAccent : Colors.grey,
                  icon: Icon(_audioOn ? Icons.hearing : Icons.hearing_disabled),
                  onPressed: widget.audioUrl == null ? null : _toggleAudio,
                ),
                if (widget.onClose != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: 'Hide panel',
                    color: Colors.grey,
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: widget.cameraUp && widget.videoUrl != null
                  ? MjpegView(url: widget.videoUrl!)
                  : Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: const Text(
                        'CAMERA BUSY\n(Chloe may be awake and using it)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orange, fontSize: 11),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal MJPEG (multipart JPEG) renderer over package:http streaming.
/// Scans for JPEG SOI/EOI markers, shows the newest complete frame, and
/// reconnects with backoff if the stream drops. Works on web and native.
class MjpegView extends StatefulWidget {
  final String url;
  const MjpegView({super.key, required this.url});

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> {
  static const Duration _reconnectDelay = Duration(seconds: 2);
  static const int _maxBufferBytes = 4 << 20; // 4MB guard against junk

  http.Client? _client;
  StreamSubscription<List<int>>? _sub;
  Uint8List? _frame;
  String? _error;
  bool _disposed = false;
  final List<int> _buffer = <int>[];

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(MjpegView old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _teardown();
      _connect();
    }
  }

  Future<void> _connect() async {
    if (_disposed) return;
    _buffer.clear();
    final client = http.Client();
    _client = client;
    try {
      final res = await client.send(http.Request('GET', Uri.parse(widget.url)));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      _sub = res.stream.listen(_onBytes,
          onError: (e) => _scheduleReconnect('$e'),
          onDone: () => _scheduleReconnect('stream ended'),
          cancelOnError: true);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      _scheduleReconnect('$e');
    }
  }

  void _onBytes(List<int> chunk) {
    _buffer.addAll(chunk);
    if (_buffer.length > _maxBufferBytes) {
      _buffer.clear(); // corrupt/non-mjpeg data — resync
      return;
    }
    final bytes = Uint8List.fromList(_buffer);
    // newest complete JPEG: last SOI before the last EOI
    int eoi = _lastIndexOfMarker(bytes, 0xD9);
    if (eoi < 0) return;
    int soi = _lastIndexOfMarker(bytes, 0xD8, before: eoi);
    if (soi < 0) return;
    final frame = bytes.sublist(soi, eoi + 2);
    _buffer.removeRange(0, eoi + 2); // keep only the remainder
    if (mounted) setState(() => _frame = frame);
  }

  int _lastIndexOfMarker(Uint8List b, int second, {int? before}) {
    for (int i = (before ?? b.length - 1); i >= 1; i--) {
      if (b[i] == second && b[i - 1] == 0xFF) return i - 1;
    }
    return -1;
  }

  void _scheduleReconnect(String why) {
    if (_disposed) return;
    if (mounted) setState(() => _error = why);
    _teardown();
    Timer(_reconnectDelay, _connect);
  }

  void _teardown() {
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _teardown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frame != null) {
      return Image.memory(
        _frame!,
        gaplessPlayback: true,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const ColoredBox(color: Colors.black),
      );
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Text(
        _error == null ? 'connecting…' : 'reconnecting…\n$_error',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.grey, fontSize: 11),
      ),
    );
  }
}
