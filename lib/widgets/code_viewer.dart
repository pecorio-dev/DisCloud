import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CodeViewer extends StatefulWidget {
  final Uint8List data;
  final String fileName;
  final String language;
  final Function(Uint8List)? onSave;

  const CodeViewer({
    super.key,
    required this.data,
    required this.fileName,
    required this.language,
    this.onSave,
  });

  @override
  State<CodeViewer> createState() => _CodeViewerState();
}

class _CodeViewerState extends State<CodeViewer> {
  late TextEditingController _controller;
  late String _originalContent;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  bool _isEditing = false;
  bool _hasChanges = false;
  double _fontSize = 14;
  bool _showLineNumbers = true;

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
    final lines = _controller.text.split('\n');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Colors
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final lineNumBg = isDark ? const Color(0xFF252526) : Colors.grey.shade100;
    final lineNumColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
    final infoBg = isDark ? Colors.grey.shade900 : Colors.grey.shade200;
    final infoText = isDark ? Colors.white70 : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(_getLanguageIcon(), size: 20),
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
              if (action == 'lines') setState(() => _showLineNumbers = !_showLineNumbers);
              if (action == 'font_up') setState(() => _fontSize = (_fontSize + 2).clamp(10, 32));
              if (action == 'font_down') setState(() => _fontSize = (_fontSize - 2).clamp(10, 32));
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'lines', child: Row(children: [
                Icon(_showLineNumbers ? Icons.check_box : Icons.check_box_outline_blank, size: 20),
                const SizedBox(width: 8), const Text('Line numbers')
              ])),
              const PopupMenuItem(value: 'font_up', child: Row(children: [Icon(Icons.add, size: 20), SizedBox(width: 8), Text('Larger')])),
              const PopupMenuItem(value: 'font_down', child: Row(children: [Icon(Icons.remove, size: 20), SizedBox(width: 8), Text('Smaller')])),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Info bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: infoBg,
            child: Row(
              children: [
                Text('${lines.length} lines', style: TextStyle(fontSize: 12, color: infoText)),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                  child: Text(widget.language.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: infoText)),
                ),
                const Spacer(),
                Text('Font: ${_fontSize.toInt()}', style: TextStyle(fontSize: 12, color: infoText)),
              ],
            ),
          ),
          // Code
          Expanded(
            child: Container(
              color: bgColor,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line numbers
                  if (_showLineNumbers)
                    Container(
                      width: 50,
                      color: lineNumBg,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: lines.length,
                        itemBuilder: (_, i) => Container(
                          height: _fontSize * 1.6,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(fontSize: _fontSize - 2, color: lineNumColor, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ),
                  // Code content
                  Expanded(
                    child: _isEditing
                        ? TextField(
                            controller: _controller,
                            maxLines: null,
                            expands: true,
                            onChanged: _onTextChanged,
                            style: TextStyle(
                              fontSize: _fontSize,
                              color: textColor,
                              fontFamily: 'monospace',
                              height: 1.6,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(8),
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(8),
                            child: SizedBox(
                              width: double.infinity,
                              child: SelectableText.rich(
                                TextSpan(
                                  children: _highlightCode(_controller.text, textColor),
                                  style: TextStyle(
                                    fontSize: _fontSize,
                                    fontFamily: 'monospace',
                                    height: 1.6,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _highlightCode(String code, Color defaultColor) {
    // Simple syntax highlighting
    final keywords = ['if', 'else', 'for', 'while', 'return', 'class', 'function', 'def', 'import', 'from', 'const', 'let', 'var', 'final', 'void', 'int', 'String', 'bool', 'true', 'false', 'null', 'async', 'await', 'try', 'catch', 'throw', 'new', 'this', 'super', 'extends', 'implements', 'override', 'static', 'private', 'public', 'protected'];
    
    final spans = <TextSpan>[];
    final lines = code.split('\n');
    
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(TextSpan(text: '\n', style: TextStyle(color: defaultColor)));
      
      final line = lines[i];
      
      // Check for comments
      if (line.trimLeft().startsWith('//') || line.trimLeft().startsWith('#')) {
        spans.add(TextSpan(text: line, style: const TextStyle(color: Colors.green)));
        continue;
      }
      
      // Check for strings
      if (line.contains('"') || line.contains("'")) {
        var remaining = line;
        while (remaining.isNotEmpty) {
          final doubleQuote = remaining.indexOf('"');
          final singleQuote = remaining.indexOf("'");
          
          int quoteStart = -1;
          String quoteChar = '';
          
          if (doubleQuote >= 0 && (singleQuote < 0 || doubleQuote < singleQuote)) {
            quoteStart = doubleQuote;
            quoteChar = '"';
          } else if (singleQuote >= 0) {
            quoteStart = singleQuote;
            quoteChar = "'";
          }
          
          if (quoteStart < 0) {
            _addHighlightedWords(spans, remaining, keywords, defaultColor);
            break;
          }
          
          if (quoteStart > 0) {
            _addHighlightedWords(spans, remaining.substring(0, quoteStart), keywords, defaultColor);
          }
          
          final quoteEnd = remaining.indexOf(quoteChar, quoteStart + 1);
          if (quoteEnd < 0) {
            spans.add(TextSpan(text: remaining.substring(quoteStart), style: const TextStyle(color: Colors.orange)));
            break;
          }
          
          spans.add(TextSpan(text: remaining.substring(quoteStart, quoteEnd + 1), style: const TextStyle(color: Colors.orange)));
          remaining = remaining.substring(quoteEnd + 1);
        }
        continue;
      }
      
      _addHighlightedWords(spans, line, keywords, defaultColor);
    }
    
    return spans;
  }

  void _addHighlightedWords(List<TextSpan> spans, String text, List<String> keywords, Color defaultColor) {
    final words = text.split(RegExp(r'(\s+|(?=[^\w])|(?<=[^\w]))'));
    for (final word in words) {
      if (keywords.contains(word)) {
        spans.add(TextSpan(text: word, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)));
      } else if (RegExp(r'^\d+$').hasMatch(word)) {
        spans.add(TextSpan(text: word, style: const TextStyle(color: Colors.purple)));
      } else {
        spans.add(TextSpan(text: word, style: TextStyle(color: defaultColor)));
      }
    }
  }

  IconData _getLanguageIcon() {
    switch (widget.language) {
      case 'dart': return Icons.flutter_dash;
      case 'python': return Icons.code;
      case 'javascript': case 'typescript': return Icons.javascript;
      case 'html': return Icons.html;
      case 'css': return Icons.css;
      case 'json': return Icons.data_object;
      default: return Icons.code;
    }
  }
}
