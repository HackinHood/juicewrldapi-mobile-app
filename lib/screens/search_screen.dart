import 'package:flutter/material.dart';
import 'package:music_library_app/models/media_item.dart';
import 'package:music_library_app/services/storage_service.dart';
import 'package:music_library_app/widgets/media_item_card.dart';
import 'package:music_library_app/utils/restricted.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<MediaItem> _searchResults = [];
  bool _isSearching = false;
  String _lastQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Search music...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: _onSearchChanged,
          onSubmitted: _onSearchSubmitted,
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSearch,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty && _lastQuery.isNotEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No results found', style: TextStyle(fontSize: 18)),
            Text('Try a different search term', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_lastQuery.isEmpty) {
      return _buildSearchSuggestions();
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        return MediaItemCard(
          mediaItem: item,
          onTap: () => _playItem(item),
          onDownload: () => _downloadItem(item),
        );
      },
    );
  }

  Widget _buildSearchSuggestions() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Search for music', style: TextStyle(fontSize: 18)),
          Text('Enter a song, artist, or album name', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _lastQuery = '';
      });
      return;
    }

    if (query.length >= 2) {
      _performSearch(query);
    }
  }

  void _onSearchSubmitted(String query) {
    if (query.trim().isNotEmpty) {
      _performSearch(query);
    }
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isSearching = true;
    });

    try {
      final results = await StorageService.searchMediaItems(query);
      setState(() {
        _searchResults = results.where((item) => !isRestrictedMediaItem(item)).toList();
        _lastQuery = query;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _lastQuery = '';
    });
  }

  void _playItem(MediaItem item) {
  }

  void _downloadItem(MediaItem item) {
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
