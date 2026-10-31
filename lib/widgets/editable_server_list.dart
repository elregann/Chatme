// editable_server_list.dart

import 'package:flutter/material.dart';
import '../services/server_lists.dart';

/// A titled card of servers with a cross on each row and an add row at the end.
class EditableServerList extends StatefulWidget {
  final String title;
  final String description;
  final List<String> servers;
  final List<String> defaults;
  final String addLabel;

  final String hint;
  final bool fileServer;

  /// Null hides the add row, for a list that is full.
  final Future<ListEdit> Function(String input)? onSubmit;
  final void Function(String url) onRemove;
  final String Function(String url)? statusLabel;
  final Color Function(String url)? statusColor;
  final String? warning;

  const EditableServerList({
    super.key,
    required this.title,
    required this.description,
    required this.servers,
    required this.defaults,
    required this.addLabel,
    required this.hint,
    required this.fileServer,
    required this.onSubmit,
    required this.onRemove,
    this.statusLabel,
    this.statusColor,
    this.warning,
  });

  @override
  State<EditableServerList> createState() => _EditableServerListState();
}

class _EditableServerListState extends State<EditableServerList> {
  final _controller = TextEditingController();
  bool _editing = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() => setState(() {
        _editing = true;
        _error = null;
      });

  void _close() => setState(() {
        _editing = false;
        _busy = false;
        _error = null;
        _controller.clear();
      });

  Future<void> _submit() async {
    final submit = widget.onSubmit;
    if (_busy || submit == null) return;
    if (_controller.text.trim().isEmpty) {
      _close();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final edit = await submit(_controller.text);
    if (!mounted) return;
    if (edit.ok) {
      _close();
      return;
    }
    setState(() {
      _busy = false;
      _error = changeMessage(edit.change, fileServer: widget.fileServer);
    });
  }

  Widget _addRow(Color textSecondary) {
    if (!_editing) {
      return GestureDetector(
        onTap: _open,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.addLabel, style: TextStyle(fontSize: 14, color: textSecondary)),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.add_rounded, size: 20, color: textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  cursorColor: textSecondary,
                  style: const TextStyle(fontSize: 14),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration.collapsed(
                    hintText: widget.hint,
                    hintStyle: TextStyle(fontSize: 14, color: textSecondary),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _submit,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: textSecondary),
                        )
                      : Icon(Icons.check_rounded, size: 20, color: textSecondary),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8);
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textPrimary = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark ? Colors.white54 : Colors.black45;

    final rows = <Widget>[];
    for (var i = 0; i < widget.servers.length; i++) {
      final url = widget.servers[i];
      if (i > 0) rows.add(Divider(height: 0.5, thickness: 0.5, color: borderColor, indent: 16));
      rows.add(_row(url, textPrimary, textSecondary));
    }
    if (widget.onSubmit != null) {
      if (rows.isNotEmpty) {
        rows.add(Divider(height: 0.5, thickness: 0.5, color: borderColor, indent: 16));
      }
      rows.add(_addRow(textSecondary));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
        ),
        if (widget.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(widget.description, style: TextStyle(fontSize: 13, height: 1.35, color: textSecondary)),
        ],
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 0.5),
          ),
          child: Column(children: rows),
        ),
        if (widget.warning != null) ...[
          const SizedBox(height: 8),
          Text(widget.warning!, style: const TextStyle(fontSize: 12, height: 1.35, color: Colors.orange)),
        ],
      ],
    );
  }

  Widget _row(String url, Color textPrimary, Color textSecondary) {
    final isDefault = ServerLists.isDefault(url, widget.defaults);
    final status = widget.statusLabel?.call(url);
    final color = widget.statusColor?.call(url);

    final subtitle = <Widget>[
      if (status != null)
        Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
      if (status != null && isDefault)
        Text(' · ', style: TextStyle(fontSize: 11, color: textSecondary)),
      if (isDefault) Text('Default', style: TextStyle(fontSize: 11, color: textSecondary)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          if (color != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ServerAddress.displayHost(url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: textPrimary),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: subtitle),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: () => widget.onRemove(url),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.close_rounded, size: 20, color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
