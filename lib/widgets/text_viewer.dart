import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TextViewer extends StatefulWidget {
  final Uint8List data;
  final String fileName;
  final Function(Uint8List)? onSave;

  const TextViewer({
    super.key,
    required this.data,
    required this.fileName,
    this.onSave,
  });

  @override
  State<TextViewer> createState() => _TextViewerState();
}

class _TextViewerState extends State<TextViewer> {
  late TextEditingController _controller;
  late String _originalContent;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  bool _isEditing = false;
  bool _hasChanges = false;
  double _fontSize = 14;

  @override
  void initState() {
    super.initState();
    _originalContent = utf8.decode(widget.data, allowMalformed: true);
    _controller = TextEditingController(text: _originalContent);
    _undoStack.add(_originalContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    if (_undoStack.isEmpty || _undoStack.last != text) {
      _undoStack.add(text);
      _redoStack.clear();
      if (_undoStack.length > 100) _undoStack.removeAt(0);
    }
    setState(() => _hasChanges = text != _originalContent);
  }

  void _undo() {
    if (_undoStack.length > 1) {
      _redoStack.add(_undoStack.removeLast());
      _controller.text = _undoStack.last;
      setState(() => _hasChanges = _controller.text != _originalContent);
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      final text = _redoStack.removeLast();
      _undoStack.add(text);
      _controller.text = text;
      setState(() => _hasChanges = _controller.text != _originalContent);
    }
  }

  void _save() {
    if (widget.onSave != null) {
      widget.onSave!(Uint8List.fromList(utf8.encode(_controller.text)));
      _originalContent = _controller.text;
      setState(() => _hasChanges = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved!'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _controller.text.split('\n').length;
    final words = _controller.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final chars = _controller.text.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.article, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.fileName, overflow: TextOverflow.ellipsis)),
            if (_hasChanges) const Text(' *', style: TextStyle(color: Colors.orange)),
          ],
        ),
        actions: [
          if (_isEditing) ...[
            IconButton(icon: const Icon(Icons.undo), onPressed: _undoStack.length > 1 ? _undo : null, tooltip: 'Undo'),
            IconButton(icon: const Icon(Icons.redo), onPressed: _redoStack.isNotEmpty ? _redo : null, tooltip: 'Redo'),
            IconButton(icon: const Icon(Icons.save), onPressed: _hasChanges && widget.onSave != null ? _save : null, tooltip: 'Save'),
          ],
          IconButton(
            icon: Icon(_isEditing ? Icons.visibility : Icons.edit),
            onPressed: () => setState(() => _isEditing = !_isEditing),
            tooltip: _isEditing ? 'View' : 'Edit',
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _controller.text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied!')));
            },
            tooltip: 'Copy',
          ),
          PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'font_up') setState(() => _fontSize = (_fontSize + 2).clamp(10, 32));
              if (action == 'font_down') setState(() => _fontSize = (_fontSize - 2).clamp(10, 32));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'font_up', child: Row(children: [Icon(Icons.add, size: 20), SizedBox(width: 8), Text('Larger')])),
              PopupMenuItem(value: 'font_down', child: Row(children: [Icon(Icons.remove, size: 20), SizedBox(width: 8), Text('Smaller')])),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('$lines lines', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                Text('$words words', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                Text('$chars chars', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                Text('Font: ${_fontSize.toInt()}', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Container(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              child: _isEditing
                  ? TextField(
                      controller: _controller,
                      maxLines: null,
                      expands: true,
                      onChanged: _onTextChanged,
                      style: TextStyle(
                        fontSize: _fontSize,
                        color: isDark ? Colors.white : Colors.black,
                        fontFamily: 'monospace',
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(16),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: SelectableText(
                          _controller.text,
                          style: TextStyle(
                            fontSize: _fontSize,
                            color: isDark ? Colors.white : Colors.black,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
