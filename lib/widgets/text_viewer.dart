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
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  bool _isEditing = false;
  bool _hasChanges = false;
  bool _wordWrap = true;
  double _fontSize = 14;

  @override
  void initState() {
    super.initState();
    final content = utf8.decode(widget.data, allowMalformed: true);
    _controller = TextEditingController(text: content);
    _undoStack.add(content);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_isEditing) {
      final text = _controller.text;
      if (_undoStack.isEmpty || _undoStack.last != text) {
        _undoStack.add(text);
        _redoStack.clear();
        if (_undoStack.length > 100) _undoStack.removeAt(0);
      }
      setState(() => _hasChanges = text != utf8.decode(widget.data, allowMalformed: true));
    }
  }

  void _undo() {
    if (_undoStack.length > 1) {
      _redoStack.add(_undoStack.removeLast());
      _controller.removeListener(_onTextChanged);
      _controller.text = _undoStack.last;
      _controller.addListener(_onTextChanged);
      setState(() => _hasChanges = _controller.text != utf8.decode(widget.data, allowMalformed: true));
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      final text = _redoStack.removeLast();
      _undoStack.add(text);
      _controller.removeListener(_onTextChanged);
      _controller.text = text;
      _controller.addListener(_onTextChanged);
      setState(() => _hasChanges = _controller.text != utf8.decode(widget.data, allowMalformed: true));
    }
  }

  void _save() {
    if (widget.onSave != null) {
      widget.onSave!(Uint8List.fromList(utf8.encode(_controller.text)));
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
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _undoStack.length > 1 ? _undo : null,
              tooltip: 'Undo',
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: _redoStack.isNotEmpty ? _redo : null,
              tooltip: 'Redo',
            ),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _hasChanges && widget.onSave != null ? _save : null,
              tooltip: 'Save',
            ),
          ],
          IconButton(
            icon: Icon(_isEditing ? Icons.visibility : Icons.edit),
            onPressed: () => setState(() => _isEditing = !_isEditing),
            tooltip: _isEditing ? 'View mode' : 'Edit mode',
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _controller.text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied!')));
            },
            tooltip: 'Copy all',
          ),
          PopupMenuButton<String>(
            onSelected: (action) {
              switch (action) {
                case 'wrap':
                  setState(() => _wordWrap = !_wordWrap);
                  break;
                case 'font_up':
                  setState(() => _fontSize = (_fontSize + 2).clamp(10, 32));
                  break;
                case 'font_down':
                  setState(() => _fontSize = (_fontSize - 2).clamp(10, 32));
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'wrap', child: Row(children: [
                Icon(_wordWrap ? Icons.check_box : Icons.check_box_outline_blank, size: 20),
                const SizedBox(width: 8), const Text('Word wrap')
              ])),
              const PopupMenuItem(value: 'font_up', child: Row(children: [
                Icon(Icons.text_increase, size: 20), SizedBox(width: 8), Text('Increase font')
              ])),
              const PopupMenuItem(value: 'font_down', child: Row(children: [
                Icon(Icons.text_decrease, size: 20), SizedBox(width: 8), Text('Decrease font')
              ])),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('$lines lines'),
                Text('$words words'),
                Text('$chars chars'),
              ],
            ),
          ),
          Expanded(
            child: _isEditing
                ? TextField(
                    controller: _controller,
                    maxLines: null,
                    expands: true,
                    style: TextStyle(fontSize: _fontSize),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _controller.text,
                      style: TextStyle(fontSize: _fontSize),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
