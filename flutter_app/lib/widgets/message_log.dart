import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';
import '../core/rosbridge_client.dart';

/// Real-time pub/sub message log viewer
class MessageLog extends StatefulWidget {
  const MessageLog({super.key});

  @override
  State<MessageLog> createState() => _MessageLogState();
}

class _MessageLogState extends State<MessageLog> {
  final List<RosbridgeMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _subscription;
  bool _autoScroll = true;
  bool _expanded = false;
  static const int _maxMessages = 100;

  @override
  void initState() {
    super.initState();
    _subscribeToMessages();
  }

  void _subscribeToMessages() {
    final robot = context.read<RobotConnection>();
    _subscription = robot.client.messageLog.listen((msg) {
      setState(() {
        _messages.add(msg);
        // Keep buffer bounded
        if (_messages.length > _maxMessages) {
          _messages.removeAt(0);
        }
      });
      // Auto-scroll to bottom
      if (_autoScroll && _scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.terminal, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Message Log',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  // Message count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_messages.length}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Auto-scroll toggle
                  IconButton(
                    icon: Icon(
                      _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _autoScroll = !_autoScroll),
                    tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
                    visualDensity: VisualDensity.compact,
                  ),
                  // Clear button
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => setState(() => _messages.clear()),
                    tooltip: 'Clear log',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
          // Message list (collapsible)
          if (_expanded)
            Container(
              height: 250,
              decoration: const BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet.\nConnect to a robot to see pub/sub traffic.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return _MessageTile(message: _messages[index]);
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  final RosbridgeMessage message;

  const _MessageTile({required this.message});

  @override
  Widget build(BuildContext context) {
    final isSent = message.direction == MessageDirection.sent;
    final color = isSent ? Colors.cyan : Colors.lightGreen;
    final arrow = isSent ? '→' : '←';
    final time = '${message.timestamp.hour.toString().padLeft(2, '0')}:'
        '${message.timestamp.minute.toString().padLeft(2, '0')}:'
        '${message.timestamp.second.toString().padLeft(2, '0')}.'
        '${message.timestamp.millisecond.toString().padLeft(3, '0')}';

    return InkWell(
      onTap: () => _showMessageDetail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timestamp
            Text(
              time,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(width: 8),
            // Direction arrow
            Text(
              arrow,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            // Op type
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: _opColor(message.op).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                message.op,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: _opColor(message.op),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Topic/service
            Expanded(
              child: Text(
                message.topic ?? message.service ?? '',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey[300],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _opColor(String op) {
    switch (op) {
      case 'subscribe':
        return Colors.blue;
      case 'unsubscribe':
        return Colors.orange;
      case 'publish':
        return Colors.green;
      case 'call_service':
        return Colors.purple;
      case 'service_response':
        return Colors.purple;
      case 'advertise':
        return Colors.teal;
      case 'unadvertise':
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  void _showMessageDetail(BuildContext context) {
    final prettyJson = const JsonEncoder.withIndent('  ').convert(message.data);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              message.direction == MessageDirection.sent
                  ? Icons.arrow_forward
                  : Icons.arrow_back,
              color: message.direction == MessageDirection.sent
                  ? Colors.cyan
                  : Colors.lightGreen,
            ),
            const SizedBox(width: 8),
            Text(message.op.toUpperCase()),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            prettyJson,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
