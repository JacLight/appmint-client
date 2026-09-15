import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../controller.dart';
import '../models.dart';
import '../theme.dart';

/// The conversation body: queue banner, bubbles, system lines, typing, composer.
/// Embed it anywhere; [AppmintSupportChatScreen] is the ready-made full screen.
class AppmintChatView extends StatefulWidget {
  final AppmintChatController controller;
  final AppmintChatTheme theme;
  /// Lets the customer attach photos. The app supplies the picker (camera,
  /// gallery, files — its choice); return null/empty to cancel. When omitted
  /// there is no attach button.
  final Future<List<AppmintChatAttachment>?> Function(BuildContext context)? onPickAttachments;
  const AppmintChatView({super.key, required this.controller, this.theme = const AppmintChatTheme(), this.onPickAttachments});

  @override
  State<AppmintChatView> createState() => _AppmintChatViewState();
}

class _AppmintChatViewState extends State<AppmintChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  void _onChange() {
    final n = widget.controller.messages.length;
    if (n != _seen) {
      _seen = n;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _scroll.offset > 0) {
          _scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final t = _input.text;
    if (t.trim().isEmpty) return;
    _input.clear();
    widget.controller.typing(false);
    widget.controller.send(t);
  }

  Future<void> _attach() async {
    final pick = widget.onPickAttachments;
    if (pick == null) return;
    final files = await pick(context);
    if (files == null || files.isEmpty) return;
    final t = _input.text;
    _input.clear();
    widget.controller.sendAttachments(files, text: t);
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.theme;
    final base = TextStyle(fontFamily: th.fontFamily, color: th.text);
    return DefaultTextStyle.merge(
      style: base,
      child: ColoredBox(
        color: th.background,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final c = widget.controller;
            return Column(
              children: [
                _Banner(controller: c, theme: th),
                Expanded(child: _body(c, th)),
                _Composer(
                  controller: _input,
                  theme: th,
                  enabled: c.canSend,
                  hint: c.canSend ? 'Message ${c.counterpartName}…' : 'Connecting…',
                  onSend: _send,
                  onTyping: c.typing,
                  onAttach: widget.onPickAttachments == null ? null : _attach,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(AppmintChatController c, AppmintChatTheme th) {
    if (c.error != null && c.messages.isEmpty) {
      return _Center(
        theme: th,
        icon: Icons.cloud_off_rounded,
        title: c.error!,
        action: TextButton(onPressed: c.retry, child: const Text('Try again')),
      );
    }
    if (c.loadingHistory && c.messages.isEmpty) {
      return Center(child: CircularProgressIndicator(color: th.accent));
    }
    if (c.messages.isEmpty) {
      return _Center(theme: th, icon: Icons.support_agent_rounded, title: c.config.supportName, subtitle: c.config.welcome);
    }
    final showTyping = c.peerTyping || (c.aiTyping && (c.messages.isEmpty || c.messages.last.content.isEmpty));
    final n = c.messages.length;
    // Reversed: index 0 is the newest, drawn at the bottom. The view opens at
    // the latest message and stays there as replies and images arrive, whatever
    // their height turns out to be.
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: n + (showTyping ? 1 : 0),
      itemBuilder: (context, ri) {
        if (showTyping && ri == 0) return _TypingDots(theme: th);
        final i = n - 1 - (showTyping ? ri - 1 : ri);
        final m = c.messages[i];
        final prev = i > 0 ? c.messages[i - 1] : null;
        final showDay = prev == null || !_sameDay(prev.sentAt, m.sentAt);
        return Column(
          children: [
            if (showDay) _DayLine(when: m.sentAt, theme: th),
            if (m.isSystem) _SystemLine(text: m.content, theme: th) else _Bubble(m: m, mine: m.mine(c.myEmail), theme: th),
          ],
        );
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Banner extends StatelessWidget {
  final AppmintChatController controller;
  final AppmintChatTheme theme;
  const _Banner({required this.controller, required this.theme});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    String? text;
    IconData icon = Icons.info_outline_rounded;
    Color color = theme.muted;
    if (c.ended) {
      text = 'This chat was closed. Send a message to start again.';
      icon = Icons.check_circle_outline_rounded;
    } else if (c.connection == AppmintChatConnection.failed && c.messages.isNotEmpty) {
      text = c.error ?? 'Not connected';
      icon = Icons.cloud_off_rounded;
      color = theme.danger;
    } else if (c.queue != null && c.agent == null) {
      final q = c.queue!;
      final wait = q.estimatedWaitSeconds;
      text = q.position <= 1
          ? 'You are next — someone will be with you shortly.'
          : 'You are #${q.position} in line${wait != null && wait > 0 ? ' · about ${(wait / 60).ceil()} min' : ''}.';
      icon = Icons.hourglass_top_rounded;
    } else if (c.agent != null) {
      text = '${c.agent!.name} is on this chat.';
      icon = Icons.support_agent_rounded;
      color = theme.success;
    }
    if (text == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: theme.surface, border: Border(bottom: BorderSide(color: theme.line))),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class _Center extends StatelessWidget {
  final AppmintChatTheme theme;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const _Center({required this.theme, required this.icon, required this.title, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: theme.muted),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: theme.muted, height: 1.35)),
            ],
            if (action != null) ...[const SizedBox(height: 8), action!],
          ]),
        ),
      );
}

class _DayLine extends StatelessWidget {
  final DateTime when;
  final AppmintChatTheme theme;
  const _DayLine({required this.when, required this.theme});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = now.year == when.year && now.month == when.month && now.day == when.day;
    const mo = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final label = today ? 'Today' : '${mo[when.month]} ${when.day}${when.year != now.year ? ', ${when.year}' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(label, style: TextStyle(fontSize: 11.5, color: theme.muted, fontWeight: FontWeight.w600, letterSpacing: .4)),
    );
  }
}

class _SystemLine extends StatelessWidget {
  final String text;
  final AppmintChatTheme theme;
  const _SystemLine({required this.text, required this.theme});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: theme.muted, fontStyle: FontStyle.italic)),
      );
}

class _Bubble extends StatelessWidget {
  final AppmintChatMessage m;
  final bool mine;
  final AppmintChatTheme theme;
  const _Bubble({required this.m, required this.mine, required this.theme});

  @override
  Widget build(BuildContext context) {
    final r = Radius.circular(theme.radius);
    final failed = m.status == 'failed';
    final time = '${m.sentAt.hour.toString().padLeft(2, '0')}:${m.sentAt.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: m.content.isEmpty && m.files.isNotEmpty ? const EdgeInsets.all(6) : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
            decoration: BoxDecoration(
              color: mine ? theme.accent : theme.surface,
              borderRadius: BorderRadius.only(
                topLeft: r, topRight: r,
                bottomLeft: Radius.circular(mine ? theme.radius : 4),
                bottomRight: Radius.circular(mine ? 4 : theme.radius),
              ),
              border: mine ? null : Border.all(color: theme.line, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!mine && m.isAi)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('Assistant', style: TextStyle(fontSize: 11, color: theme.muted, fontWeight: FontWeight.w700)),
                  ),
                if (m.content.isNotEmpty)
                  mine
                      ? Text(m.content, style: TextStyle(color: theme.onAccent, height: 1.35))
                      : MarkdownBody(
                          data: m.content,
                          selectable: false,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(color: theme.text, height: 1.35, fontFamily: theme.fontFamily),
                            listBullet: TextStyle(color: theme.text, fontFamily: theme.fontFamily),
                            strong: TextStyle(color: theme.text, fontWeight: FontWeight.w700),
                            a: TextStyle(color: theme.accent, decoration: TextDecoration.underline),
                            code: TextStyle(color: theme.text, backgroundColor: theme.background, fontFamily: 'monospace'),
                          ),
                        ),
                for (final f in m.files)
                  if (appmintFileIsImage(f))
                    _ImageThumb(file: f, theme: theme, mine: mine, dim: m.status == 'pending')
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.attach_file_rounded, size: 14, color: mine ? theme.onAccent : theme.muted),
                        const SizedBox(width: 4),
                        Flexible(child: Text((f['name'] ?? f['url'] ?? 'file').toString(), overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: mine ? theme.onAccent : theme.text))),
                      ]),
                    ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
            child: Text(
              failed ? 'Not sent — tap to retry' : mine ? '$time · ${_status(m.status)}' : time,
              style: TextStyle(fontSize: 10.5, color: failed ? theme.danger : theme.muted),
            ),
          ),
        ],
      ),
    );
  }

  static String _status(String s) {
    switch (s) {
      case 'pending':
        return 'sending';
      case 'read':
        return 'read';
      case 'delivered':
        return 'delivered';
      default:
        return 'sent';
    }
  }
}

class _TypingDots extends StatelessWidget {
  final AppmintChatTheme theme;
  const _TypingDots({required this.theme});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(theme.radius),
            border: Border.all(color: theme.line, width: 1.2),
          ),
          child: Text('typing…', style: TextStyle(color: theme.muted, fontSize: 13)),
        ),
      );
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final AppmintChatTheme theme;
  final bool enabled;
  final String hint;
  final VoidCallback onSend;
  final ValueChanged<bool> onTyping;
  final VoidCallback? onAttach;
  const _Composer({
    required this.controller,
    required this.theme,
    required this.enabled,
    required this.hint,
    required this.onSend,
    required this.onTyping,
    this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    final pill = OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(color: theme.line, width: 1.4),
    );
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(color: theme.surface, border: Border(top: BorderSide(color: theme.line, width: 1.2))),
        child: Row(children: [
          if (onAttach != null)
            IconButton(
              tooltip: 'Add a photo',
              onPressed: enabled ? onAttach : null,
              icon: Icon(Icons.add_photo_alternate_outlined, color: enabled ? theme.muted : theme.line),
            ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              onChanged: (v) => onTyping(v.isNotEmpty),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: TextStyle(color: theme.text, fontFamily: theme.fontFamily),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: theme.muted),
                filled: true,
                fillColor: theme.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: pill,
                enabledBorder: pill,
                disabledBorder: pill,
                focusedBorder: pill.copyWith(borderSide: BorderSide(color: theme.accent, width: 1.6)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: enabled ? theme.accent : theme.line,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onSend : null,
              child: SizedBox(width: 46, height: 46, child: Icon(Icons.send_rounded, color: theme.onAccent, size: 20)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// An image in a bubble: local bytes while uploading, the signed url after.
/// Tap for a full-screen look.
class _ImageThumb extends StatelessWidget {
  final Map<String, dynamic> file;
  final AppmintChatTheme theme;
  final bool mine;
  final bool dim;
  const _ImageThumb({required this.file, required this.theme, required this.mine, required this.dim});

  Widget _img(BoxFit fit) {
    final bytes = file['bytes'];
    if (bytes is List<int>) return Image.memory(Uint8List.fromList(bytes), fit: fit, gaplessPlayback: true);
    final url = (file['url'] ?? '').toString();
    return Image.network(url, fit: fit,
        loadingBuilder: (c, w, p) => p == null ? w : SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: theme.accent, strokeWidth: 2))),
        errorBuilder: (c, e, st) => Container(
              height: 90, alignment: Alignment.center, color: theme.line,
              child: Icon(Icons.broken_image_outlined, color: theme.muted),
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(children: [
              Positioned.fill(child: InteractiveViewer(child: Center(child: _img(BoxFit.contain)))),
              Positioned(top: 8, right: 8, child: SafeArea(child: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.pop(context)))),
            ]),
          ),
        ),
        child: Opacity(
          opacity: dim ? .6 : 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(theme.radius - 6),
            // A fixed box: the list's extent must not jump when the picture
            // arrives, or the newest image ends up clipped under the composer.
            child: SizedBox(width: 240, height: 180, child: _img(BoxFit.cover)),
          ),
        ),
      ),
    );
  }
}
