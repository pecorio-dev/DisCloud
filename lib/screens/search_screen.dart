import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cloud_file.dart';
import '../providers/cloud_provider.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _results = <SearchResult>[];
  bool _isSearching = false;
  bool _searchInContent = false;
  String _searchStatus = '';
  double _progress = 0;
  int _filesScanned = 0;
  int _totalFiles = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          _buildSearchBar(),
          if (_isSearching) _buildProgress(),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _results.clear());
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (_) => _performSearch(),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  title: const Text('Search in content'),
                  value: _searchInContent,
                  onChanged: (v) => setState(() => _searchInContent = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isSearching ? null : _performSearch,
                icon: const Icon(Icons.search),
                label: const Text('Search'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text(_searchStatus),
              const Spacer(),
              Text('$_filesScanned / $_totalFiles'),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _progress),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty && !_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(_searchController.text.isEmpty ? 'Enter a search term' : 'No results found'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _results.length,
      itemBuilder: (context, index) => _buildResultCard(_results[index]),
    );
  }

  Widget _buildResultCard(SearchResult result) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          result.isDirectory ? Icons.folder : Icons.insert_drive_file,
          color: result.isDirectory ? Colors.amber : Colors.blue,
        ),
        title: Text(result.fileName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.path, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            if (result.matchContext != null)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(result.matchContext!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12), maxLines: 3),
              ),
          ],
        ),
        trailing: Text(result.matchType, style: const TextStyle(fontSize: 12)),
        onTap: () => _navigateToResult(result),
      ),
    );
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _results.clear();
      _progress = 0;
      _filesScanned = 0;
      _searchStatus = 'Scanning...';
    });

    final provider = context.read<CloudProvider>();
    
    try {
      final allFiles = provider.currentFiles;
      _totalFiles = allFiles.length;
      
      for (int i = 0; i < allFiles.length; i++) {
        final file = allFiles[i];
        
        setState(() {
          _filesScanned = i + 1;
          _progress = (i + 1) / allFiles.length;
          _searchStatus = file.name;
        });

        if (file.name.toLowerCase().contains(query.toLowerCase())) {
          _results.add(SearchResult(
            fileName: file.name,
            path: file.path,
            isDirectory: file.isDirectory,
            matchType: 'Filename',
          ));
        }

        if (_searchInContent && !file.isDirectory) {
          await _searchInFileContent(file, query, provider);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }

    setState(() {
      _isSearching = false;
      _searchStatus = 'Done';
    });
  }

  Future<void> _searchInFileContent(CloudFile file, String query, CloudProvider provider) async {
    if (file.chunkIds.isEmpty) return;

    try {
      final data = await provider.downloadFile(file);
      if (data == null) return;

      final text = utf8.decode(data, allowMalformed: true);
      final queryLower = query.toLowerCase();
      final textLower = text.toLowerCase();
      
      int pos = 0;
      while (true) {
        final found = textLower.indexOf(queryLower, pos);
        if (found == -1) break;
        
        final start = (found - 30).clamp(0, text.length);
        final end = (found + query.length + 30).clamp(0, text.length);
        
        _results.add(SearchResult(
          fileName: file.name,
          path: file.path,
          isDirectory: false,
          matchType: 'Content',
          matchContext: '...${text.substring(start, end)}...',
          position: found,
        ));
        
        pos = found + 1;
        if (_results.length > 100) break;
      }
      
      setState(() {});
    } catch (e) {}
  }

  void _navigateToResult(SearchResult result) {
    final provider = context.read<CloudProvider>();
    final idx = result.path.lastIndexOf('/');
    final parentPath = idx > 0 ? result.path.substring(0, idx) : '/';
    provider.navigateTo(parentPath);
    Navigator.pop(context);
  }
}

class SearchResult {
  final String fileName;
  final String path;
  final bool isDirectory;
  final String matchType;
  final String? matchContext;
  final int? position;

  SearchResult({
    required this.fileName,
    required this.path,
    required this.isDirectory,
    required this.matchType,
    this.matchContext,
    this.position,
  });
}
