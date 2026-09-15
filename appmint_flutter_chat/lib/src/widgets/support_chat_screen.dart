import 'package:flutter/material.dart';
import '../config.dart';
import '../controller.dart';
import '../models.dart';
import '../theme.dart';
import 'chat_view.dart';

/// Full-screen "talk to us" — creates and owns the controller.
///
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => AppmintSupportChatScreen(config: myConfig, theme: myTheme)));
/// ```
class AppmintSupportChatScreen extends StatefulWidget {
  final AppmintChatConfig config;
  final AppmintChatTheme theme;
  final String? title;
  /// Photo picker supplied by the app (see [AppmintChatView.onPickAttachments]).
  final Future<List<AppmintChatAttachment>?> Function(BuildContext context)? onPickAttachments;
  const AppmintSupportChatScreen({super.key, required this.config, this.theme = const AppmintChatTheme(), this.title, this.onPickAttachments});

  @override
  State<AppmintSupportChatScreen> createState() => _AppmintSupportChatScreenState();
}

class _AppmintSupportChatScreenState extends State<AppmintSupportChatScreen> {
  late final AppmintChatController _c = AppmintChatController(widget.config);

  @override
  void initState() {
    super.initState();
    _c.start();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.theme;
    return Scaffold(
      backgroundColor: th.background,
      appBar: AppBar(
        backgroundColor: th.background,
        foregroundColor: th.text,
        elevation: 0,
        titleSpacing: 0,
        title: ListenableBuilder(
          listenable: _c,
          builder: (context, _) {
            final sub = _c.peerTyping
                ? 'typing…'
                : switch (_c.connection) {
                    AppmintChatConnection.authenticated => _c.agent != null ? _c.agent!.email : 'Online',
                    AppmintChatConnection.connecting || AppmintChatConnection.connected => 'Connecting…',
                    AppmintChatConnection.failed => 'Not connected',
                    AppmintChatConnection.disconnected => 'Reconnecting…',
                  };
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title ?? _c.counterpartName,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: th.text, fontFamily: th.fontFamily)),
              Text(sub, style: TextStyle(fontSize: 12, color: _c.peerTyping ? th.success : th.muted, fontFamily: th.fontFamily)),
            ]);
          },
        ),
      ),
      body: AppmintChatView(controller: _c, theme: th, onPickAttachments: widget.onPickAttachments),
    );
  }
}
