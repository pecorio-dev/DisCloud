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
  late ScrollController _scrollController;
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  bool _isEditing = false;
  bool _hasChanges = false;
  double _fontSize = 14;
  bool _showLineNumbers = true;
  String _searchQuery = '';
  int _currentSearchIndex = 0;
  List<int> _searchResults = [];

  @override
  void initState() {
    super.initState();
    final content = utf8.decode(widget.data, allowMalformed: true);
    _controller = TextEditingController(text: content);
    _scrollController = ScrollController();
    _undoStack.add(content);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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

  void _search(String query) {
    _searchResults.clear();
    if (query.isEmpty) {
      setState(() {
        _searchQuery = '';
        _currentSearchIndex = 0;
      });
      return;
    }

    final text = _controller.text.toLowerCase();
    final searchLower = query.toLowerCase();
    int index = 0;
    while (true) {
      index = text.indexOf(searchLower, index);
      if (index == -1) break;
      _searchResults.add(index);
      index++;
    }

    setState(() {
      _searchQuery = query;
      _currentSearchIndex = 0;
    });

    if (_searchResults.isNotEmpty) {
      _goToSearchResult(0);
    }
  }

  void _goToSearchResult(int index) {
    if (_searchResults.isEmpty) return;
    _currentSearchIndex = index % _searchResults.length;
    final pos = _searchResults[_currentSearchIndex];
    _controller.selection = TextSelection(baseOffset: pos, extentOffset: pos + _searchQuery.length);
    setState(() {});
  }

  void _nextSearchResult() => _goToSearchResult(_currentSearchIndex + 1);
  void _prevSearchResult() => _goToSearchResult(_currentSearchIndex - 1);

  @override
  Widget build(BuildContext context) {
    final lines = _controller.text.split('\n');
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _undoStack.length > 1 ? _undo : null,
              tooltip: 'Undo (Ctrl+Z)',
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: _redoStack.isNotEmpty ? _redo : null,
              tooltip: 'Redo (Ctrl+Y)',
            ),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _hasChanges && widget.onSave != null ? _save : null,
              tooltip: 'Save (Ctrl+S)',
            ),
          ],
          IconButton(
            icon: Icon(_isEditing ? Icons.visibility : Icons.edit),
            onPressed: () => setState(() => _isEditing = !_isEditing),
            tooltip: _isEditing ? 'View mode' : 'Edit mode',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
            tooltip: 'Search (Ctrl+F)',
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'copy', child: Row(children: [
                const Icon(Icons.copy, size: 20), const SizedBox(width: 8), const Text('Copy all')
              ])),
              PopupMenuItem(value: 'lines', child: Row(children: [
                Icon(_showLineNumbers ? Icons.check_box : Icons.check_box_outline_blank, size: 20),
                const SizedBox(width: 8), const Text('Line numbers')
              ])),
              const PopupMenuDivider(),
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
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): _showSearchDialog,
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              if (_searchQuery.isNotEmpty) _buildSearchBar(),
              _buildInfoBar(lines.length),
              Expanded(child: _buildEditor(lines, isDark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.withOpacity(0.1),
      child: Row(
        children: [
          Text('Found ${_searchResults.length} matches'),
          const Spacer(),
          Text('${_currentSearchIndex + 1}/${_searchResults.length}'),
          IconButton(icon: const Icon(Icons.arrow_upward, size: 20), onPressed: _prevSearchResult),
          IconButton(icon: const Icon(Icons.arrow_downward, size: 20), onPressed: _nextSearchResult),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => _search(''),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBar(int lineCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Text('$lineCount lines', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 16),
          Text(widget.language.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('Font: ${_fontSize.toInt()}', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildEditor(List<String> lines, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showLineNumbers)
          Container(
            width: 50,
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: lines.length,
              itemBuilder: (_, i) => Container(
                height: _fontSize * 1.5,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(fontSize: _fontSize - 2, color: Colors.grey, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        Expanded(
          child: _isEditing
              ? TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  style: TextStyle(fontSize: _fontSize, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(8),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    _controller.text,
                    style: TextStyle(fontSize: _fontSize, fontFamily: 'monospace'),
                  ),
                ),
        ),
      ],
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: _searchQuery);
        return AlertDialog(
          title: const Text('Search'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter search term'),
            onSubmitted: (value) {
              Navigator.pop(ctx);
              _search(value);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _search(controller.text);
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: _controller.text));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied!')));
        break;
      case 'lines':
        setState(() => _showLineNumbers = !_showLineNumbers);
        break;
      case 'font_up':
        setState(() => _fontSize = (_fontSize + 2).clamp(10, 32));
        break;
      case 'font_down':
        setState(() => _fontSize = (_fontSize - 2).clamp(10, 32));
        break;
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
