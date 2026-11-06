/// Wear OS Library List screen with circular-safe scrolling.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/models/library_collections.dart';
import 'package:mornye/models/local_library_item.dart';
import 'package:mornye/models/unified_library_item.dart';
import 'package:mornye/providers/library_collections_provider.dart';
import 'package:mornye/providers/local_library_provider.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/services/library_database.dart';
import 'package:mornye/services/library_row_mapper.dart';
import 'package:mornye/ui/wear/wear_layout.dart';

/// Shared empty state widget for wear library sections.
Widget _buildEmptyStateWidget(BuildContext context, bool isRound, String section) {
  final theme = Theme.of(context);
  return Center(
    child: Padding(
      padding: EdgeInsets.all(isRound ? kWearTotalCircularInset : 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_music_outlined,
            color: theme.colorScheme.onSurfaceVariant,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'No $section Found',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add music to your library on your phone',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

/// Provider for library tracks (artists, albums, tracks) with pagination.
final wearLibraryTracksProvider = FutureProvider.autoDispose
    .family<List<UnifiedLibraryItem>, ({int limit, int offset})>((ref, params) async {
  final db = LibraryDatabase.instance;
  final rows = await db.getPage(limit: params.limit, offset: params.offset);
  return rows.map(_rowToUnifiedLibraryItem).toList(growable: false);
});

UnifiedLibraryItem _rowToUnifiedLibraryItem(Map<String, dynamic> row) {
  final decoded = LibraryRowMapper.decode(row);
  final sourceId = decoded['sourceId'] as String? ?? LocalLibraryItem.legacySourceId;
  final isDownloaded = sourceId != LocalLibraryItem.legacySourceId;
  
  return UnifiedLibraryItem(
    id: decoded['id'] as String,
    trackName: decoded['trackName'] as String? ?? '',
    artistName: decoded['artistName'] as String? ?? '',
    albumName: decoded['albumName'] as String? ?? '',
    coverUrl: decoded['coverPath'] as String?,
    localCoverPath: decoded['coverPath'] as String?,
    filePath: decoded['filePath'] as String? ?? '',
    quality: null,
    addedAt: decoded['scannedAt'] != null 
        ? DateTime.tryParse(decoded['scannedAt'] as String) ?? DateTime.now()
        : DateTime.now(),
    source: isDownloaded 
        ? LibraryItemSource.downloaded 
        : LibraryItemSource.local,
    historyItem: null,
    localItem: null,
  );
}

/// Provider for library artists (aggregated from tracks).
final wearLibraryArtistsProvider = FutureProvider.autoDispose<List<_WearArtist>>((ref) async {
  final db = LibraryDatabase.instance;
  final request = QueueLibraryDbQuery(includeLocal: true, limit: 1000);
  final rows = await db.getQueueArtistPage(request);
  
  return rows.map((row) => _WearArtist(
    name: row['artist_name'] as String? ?? 'Unknown Artist',
    trackCount: row['track_count'] as int? ?? 0,
    albumCount: row['album_count'] as int? ?? 0,
  )).toList(growable: false);
});

/// Provider for library albums (aggregated from tracks).
final wearLibraryAlbumsProvider = FutureProvider.autoDispose<List<_WearAlbum>>((ref) async {
  final db = LibraryDatabase.instance;
  final request = QueueLibraryDbQuery(includeLocal: true, limit: 1000);
  final rows = await db.getQueueAlbumPage(request);
  
  return rows.map((row) => _WearAlbum(
    name: row['album_name'] as String? ?? 'Unknown Album',
    artist: row['album_artist'] as String? ?? row['artist_name'] as String? ?? 'Unknown Artist',
    trackCount: row['track_count'] as int? ?? 0,
    artworkUrl: row['cover_url'] as String?,
  )).toList(growable: false);
});

/// The main Wear OS Library screen.
///
/// Features:
/// - CustomScrollView with sliver padding to avoid circular clipping
/// - Sectioned list (Artists, Albums, Tracks, Playlists)
/// - Current track highlighting
/// - Pull-to-refresh support
class WearLibraryScreen extends ConsumerStatefulWidget {
  const WearLibraryScreen({super.key});

  @override
  ConsumerState<WearLibraryScreen> createState() => _WearLibraryScreenState();
}

class _WearLibraryScreenState extends ConsumerState<WearLibraryScreen> {
  final ScrollController _scrollController = ScrollController();
  String _selectedSection = 'Artists';
  String _searchQuery = '';

  static const List<String> _sections = [
    'Artists',
    'Albums', 
    'Tracks',
    'Playlists',
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentMediaItem = ref.watch(currentMediaItemProvider);

    return WearLayoutBuilder(
      builder: (context, safeRect, isRound) {
        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: SafeArea(
            child: Column(
              children: [
                // Section tabs
                _buildSectionTabs(context, isRound),
                
                // Search bar (optional)
                if (_selectedSection != 'Playlists') 
                  _buildSearchBar(context, isRound),
                
                // Content
                Expanded(
                  child: _buildLibraryContent(
                    context,
                    currentMediaItem.value,
                    safeRect,
                    isRound,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTabs(BuildContext context, bool isRound) {
    final theme = Theme.of(context);
    
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: isRound ? kWearTotalCircularInset : 16),
        itemCount: _sections.length,
        itemBuilder: (context, index) {
          final section = _sections[index];
          final isSelected = section == _selectedSection;
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(section),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedSection = section),
              selectedColor: theme.colorScheme.primaryContainer,
              labelStyle: theme.textTheme.labelLarge?.copyWith(
                color: isSelected 
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              side: BorderSide(
                color: isSelected 
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, bool isRound) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isRound ? kWearTotalCircularInset : 16,
        8,
        isRound ? kWearTotalCircularInset : 16,
        8,
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search ${_selectedSection.toLowerCase()}...',
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        style: theme.textTheme.bodyMedium,
        onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
      ),
    );
  }

  Widget _buildLibraryContent(
    BuildContext context,
    MediaItem? currentItem,
    Rect safeRect,
    bool isRound,
  ) {
    return CustomScrollView(
      controller: _scrollController,
      // Add top and bottom sliver padding to avoid circular clipping
      slivers: [
        // Top padding sliver - ensures first item isn't clipped at top curve
        SliverPadding(
          padding: EdgeInsets.only(
            top: isRound ? kWearTotalCircularInset : 8,
          ),
          sliver: SliverToBoxAdapter(child: const SizedBox.shrink()),
        ),
        
        // Main content - switches based on selected section
        _buildSectionContent(context, currentItem, isRound),
        
        // Bottom padding sliver - ensures last item isn't clipped at bottom curve
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: isRound ? kWearTotalCircularInset + 24 : 24,
          ),
          sliver: SliverToBoxAdapter(child: const SizedBox.shrink()),
        ),
      ],
    );
  }

  Widget _buildSectionContent(
    BuildContext context,
    MediaItem? currentItem,
    bool isRound,
  ) {
    switch (_selectedSection) {
      case 'Artists':
        return _buildArtistsSection(context, currentItem, isRound);
      case 'Albums':
        return _buildAlbumsSection(context, currentItem, isRound);
      case 'Tracks':
        return _buildTracksSection(context, currentItem, isRound);
      case 'Playlists':
        return _buildPlaylistsSection(context, currentItem, isRound);
      default:
        return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
  }

  Widget _buildArtistsSection(
    BuildContext context,
    MediaItem? currentItem,
    bool isRound,
  ) {
    final artistsAsync = ref.watch(wearLibraryArtistsProvider);
    
    return artistsAsync.when(
      data: (artists) {
        final filtered = _searchQuery.isEmpty
            ? artists
            : artists.where((a) => a.name.toLowerCase().contains(_searchQuery)).toList();
        
        if (filtered.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(context, isRound, 'Artists'),
          );
        }
        
        return SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: isRound ? kWearTotalCircularInset : 16,
          ),
          sliver: SliverList.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final artist = filtered[index];
              return _buildArtistItem(context, artist, isRound);
            },
          ),
        );
      },
      loading: () => _buildLoadingSliver(context, isRound),
      error: (error, _) => _buildErrorSliver(context, error, isRound),
    );
  }

  Widget _buildAlbumsSection(
    BuildContext context,
    MediaItem? currentItem,
    bool isRound,
  ) {
    final albumsAsync = ref.watch(wearLibraryAlbumsProvider);
    
    return albumsAsync.when(
      data: (albums) {
        final filtered = _searchQuery.isEmpty
            ? albums
            : albums.where((a) => 
                a.name.toLowerCase().contains(_searchQuery) ||
                a.artist.toLowerCase().contains(_searchQuery)
              ).toList();
        
        if (filtered.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(context, isRound, 'Albums'),
          );
        }
        
        return SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: isRound ? kWearTotalCircularInset : 16,
          ),
          sliver: SliverList.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final album = filtered[index];
              return _buildAlbumItem(context, album, isRound);
            },
          ),
        );
      },
      loading: () => _buildLoadingSliver(context, isRound),
      error: (error, _) => _buildErrorSliver(context, error, isRound),
    );
  }

  Widget _buildTracksSection(
    BuildContext context,
    MediaItem? currentItem,
    bool isRound,
  ) {
    // Use a paginated list for tracks
    return _TracksListView(
      searchQuery: _searchQuery,
      currentItem: currentItem,
      isRound: isRound,
    );
  }

  Widget _buildPlaylistsSection(
    BuildContext context,
    MediaItem? currentItem,
    bool isRound,
  ) {
    final collectionsAsync = ref.watch(libraryCollectionsProvider);
    
    return collectionsAsync.when(
      data: (collections) {
        final playlists = collections.playlists;
        final filtered = _searchQuery.isEmpty
            ? playlists
            : playlists.where((p) => p.name.toLowerCase().contains(_searchQuery)).toList();
        
        if (filtered.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(context, isRound, 'Playlists'),
          );
        }
        
        return SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: isRound ? kWearTotalCircularInset : 16,
          ),
          sliver: SliverList.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final playlist = filtered[index];
              return _buildPlaylistItem(context, playlist, isRound);
            },
          ),
        );
      },
      loading: () => _buildLoadingSliver(context, isRound),
      error: (error, _) => _buildErrorSliver(context, error, isRound),
    );
  }

  Widget _buildArtistItem(
    BuildContext context,
    _WearArtist artist,
    bool isRound,
  ) {
    final theme = Theme.of(context);
    
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onArtistTap(context, artist),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isRound ? 12 : 16,
            vertical: 12,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: isRound ? 24 : 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.person,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: isRound ? 28 : 32,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      artist.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${artist.trackCount} tracks · ${artist.albumCount} albums',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumItem(
    BuildContext context,
    _WearAlbum album,
    bool isRound,
  ) {
    final theme = Theme.of(context);
    final size = isRound ? 48.0 : 56.0;
    
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onAlbumTap(context, album),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isRound ? 12 : 16,
            vertical: 12,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: album.artworkUrl != null
                    ? Image.network(
                        album.artworkUrl!,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholderArt(size, theme),
                      )
                    : _placeholderArt(size, theme),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      album.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      album.artist,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${album.trackCount} tracks',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistItem(
    BuildContext context,
    LibraryPlaylist playlist,
    bool isRound,
  ) {
    final theme = Theme.of(context);
    final size = isRound ? 48.0 : 56.0;
    
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onPlaylistTap(context, playlist),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isRound ? 12 : 16,
            vertical: 12,
          ),
          child: Row(
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: theme.colorScheme.primaryContainer,
                ),
                child: Icon(
                  Icons.queue_music,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: size * 0.5,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      playlist.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${playlist.trackIds.length} tracks',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderArt(double size, ThemeData theme) {
    return Container(
      width: size,
      height: size,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        color: theme.colorScheme.onSurfaceVariant,
        size: size * 0.4,
      ),
    );
  }

  void _onArtistTap(BuildContext context, _WearArtist artist) {
    // Navigate to artist detail or play artist tracks
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Artist: ${artist.name}')),
    );
  }

  void _onAlbumTap(BuildContext context, _WearAlbum album) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Album: ${album.name} by ${album.artist}')),
    );
  }

  void _onPlaylistTap(BuildContext context, LibraryPlaylist playlist) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playlist: ${playlist.name}')),
    );
  }

  Widget _buildLoadingSliver(BuildContext context, bool isRound) {
    final theme = Theme.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: theme.colorScheme.primary,
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              'Loading...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorSliver(BuildContext context, Object error, bool isRound) {
    final theme = Theme.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(isRound ? kWearTotalCircularInset : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'Failed to Load',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isRound, String section) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isRound ? kWearTotalCircularInset : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_music_outlined,
              color: theme.colorScheme.onSurfaceVariant,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'No $section Found',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : 'Add music to your library on your phone',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A paginated tracks list view for the Tracks section.
class _TracksListView extends ConsumerStatefulWidget {
  const _TracksListView({
    required this.searchQuery,
    required this.currentItem,
    required this.isRound,
  });

  final String searchQuery;
  final MediaItem? currentItem;
  final bool isRound;

  @override
  ConsumerState<_TracksListView> createState() => _TracksListViewState();
}

class _TracksListViewState extends ConsumerState<_TracksListView> {
  static const int _pageSize = 50;
  final List<UnifiedLibraryItem> _tracks = [];
  int _offset = 0;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    
    setState(() => _isLoading = true);
    
    try {
      final newTracks = await ref.read(
        wearLibraryTracksProvider(
          (limit: _pageSize, offset: _offset),
        ).future,
      );
      
      if (!mounted) return;
      
      setState(() {
        _tracks.addAll(newTracks);
        _offset += newTracks.length;
        _hasMore = newTracks.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.searchQuery.isEmpty
        ? _tracks
        : _tracks.where((t) => 
            t.trackName.toLowerCase().contains(widget.searchQuery) ||
            t.trackArtist.toLowerCase().contains(widget.searchQuery) ||
            t.albumName.toLowerCase().contains(widget.searchQuery)
          ).toList();

    if (filtered.isEmpty && !_isLoading) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyStateWidget(context, widget.isRound, 'Tracks'),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isRound ? kWearTotalCircularInset : 16,
      ),
      sliver: SliverList.separated(
        itemCount: filtered.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == filtered.length) {
            return _buildLoadingIndicator(context);
          }
          final track = filtered[index];
          return _buildTrackItem(context, track, widget.currentItem, widget.isRound);
        },
      ),
    );
  }

  Widget _buildLoadingIndicator(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildTrackItem(
    BuildContext context,
    UnifiedLibraryItem track,
    MediaItem? currentItem,
    bool isRound,
  ) {
    final theme = Theme.of(context);
    final isCurrent = _isCurrentTrack(track, currentItem);
    final size = isRound ? 48.0 : 56.0;
    
    return Material(
      color: isCurrent 
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onTrackTap(context, track),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isRound ? 12 : 16,
            vertical: 10,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: track.coverUrl != null
                    ? Image.network(
                        track.coverUrl!,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholderArt(size, theme),
                      )
                    : _placeholderArt(size, theme),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.trackName.isEmpty ? 'Unknown Track' : track.trackName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                        color: isCurrent 
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      track.trackArtist.isEmpty ? 'Unknown Artist' : track.trackArtist,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                Icon(
                  Icons.equalizer,
                  color: theme.colorScheme.primary,
                  size: 24,
                )
              else
                Icon(
                  Icons.play_arrow,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderArt(double size, ThemeData theme) {
    return Container(
      width: size,
      height: size,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        color: theme.colorScheme.onSurfaceVariant,
        size: size * 0.4,
      ),
    );
  }

  bool _isCurrentTrack(UnifiedLibraryItem item, MediaItem? currentItem) {
    if (currentItem == null) return false;
    
    final source = currentItem.extras?['source']?.toString() ?? '';
    return source == item.filePath || currentItem.id == item.id;
  }

  void _onTrackTap(BuildContext context, UnifiedLibraryItem track) {
    final controller = ref.read(musicPlayerControllerProvider);
    
    if (track.localItem != null) {
      controller.playSingle(playableFromLocal(track.localItem!));
    } else if (track.historyItem != null) {
      controller.playSingle(playableFromHistory(track.historyItem!));
    }
  }
}

/// Simple data class for artist info in Wear library.
class _WearArtist {
  const _WearArtist({
    required this.name,
    required this.trackCount,
    required this.albumCount,
  });

  final String name;
  final int trackCount;
  final int albumCount;
}

/// Simple data class for album info in Wear library.
class _WearAlbum {
  const _WearAlbum({
    required this.name,
    required this.artist,
    required this.trackCount,
    this.artworkUrl,
  });

  final String name;
  final String artist;
  final int trackCount;
  final String? artworkUrl;
}

  Widget _buildLibraryItem(
    BuildContext context,
    UnifiedLibraryItem item,
    MediaItem? currentItem,
    bool isRound,
  ) {
    final theme = Theme.of(context);
    final isCurrent = _isCurrentTrack(item, currentItem);
    
    return Material(
      color: isCurrent 
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onItemTap(context, item),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isRound ? 12 : 16,
            vertical: 12,
          ),
          child: Row(
            children: [
              // Artwork/Icon
              _buildItemLeading(context, item, isRound),
              
              const SizedBox(width: 12),
              
              // Title and subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getItemTitle(item),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                        color: isCurrent 
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_getItemSubtitle(item) != null)
                      Text(
                        _getItemSubtitle(item)!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              
              // Track count or play indicator
              _buildItemTrailing(context, item, isCurrent, isRound),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemLeading(
    BuildContext context,
    UnifiedLibraryItem item,
    bool isRound,
  ) {
    final theme = Theme.of(context);
    final size = isRound ? 48.0 : 56.0;
    
    if (item.type == UnifiedLibraryItemType.artist) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.person,
          color: theme.colorScheme.onPrimaryContainer,
          size: size * 0.5,
        ),
      );
    } else if (item.type == UnifiedLibraryItemType.album) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: item.artworkUrl != null
            ? Image.network(
                item.artworkUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholderArt(size, theme),
              )
            : _placeholderArt(size, theme),
      );
    } else if (item.type == UnifiedLibraryItemType.playlist) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.primaryContainer,
        ),
        child: Icon(
          Icons.queue_music,
          color: theme.colorScheme.onPrimaryContainer,
          size: size * 0.5,
        ),
      );
    } else {
      // Track
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: item.artworkUrl != null
            ? Image.network(
                item.artworkUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholderArt(size, theme),
              )
            : _placeholderArt(size, theme),
      );
    }
  }

  Widget _placeholderArt(double size, ThemeData theme) {
    return Container(
      width: size,
      height: size,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        color: theme.colorScheme.onSurfaceVariant,
        size: size * 0.4,
      ),
    );
  }

  Widget _buildItemTrailing(
    BuildContext context,
    UnifiedLibraryItem item,
    bool isCurrent,
    bool isRound,
  ) {
    final theme = Theme.of(context);
    
    if (isCurrent) {
      return Icon(
        Icons.equalizer,
        color: theme.colorScheme.primary,
        size: 24,
      );
    }
    
    if (item.type == UnifiedLibraryItemType.artist ||
        item.type == UnifiedLibraryItemType.album ||
        item.type == UnifiedLibraryItemType.playlist) {
      return Text(
        '${item.trackCount} tracks',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  bool _isCurrentTrack(UnifiedLibraryItem item, MediaItem? currentItem) {
    if (currentItem == null || item.type != UnifiedLibraryItemType.track) {
      return false;
    }
    
    final source = currentItem.extras?['source']?.toString() ?? '';
    return source == item.filePath || currentItem.id == item.id;
  }

  String _getItemTitle(UnifiedLibraryItem item) {
    switch (item.type) {
      case UnifiedLibraryItemType.artist:
        return item.trackArtist;
      case UnifiedLibraryItemType.album:
        return item.albumName;
      case UnifiedLibraryItemType.track:
        return item.trackName.isEmpty ? 'Unknown Track' : item.trackName;
      case UnifiedLibraryItemType.playlist:
        return item.trackName.isEmpty ? 'Unknown Playlist' : item.trackName;
    }
  }

  String? _getItemSubtitle(UnifiedLibraryItem item) {
    switch (item.type) {
      case UnifiedLibraryItemType.artist:
        return '${item.trackCount} tracks';
      case UnifiedLibraryItemType.album:
        return item.trackArtist.isEmpty ? null : item.trackArtist;
      case UnifiedLibraryItemType.track:
        return item.trackArtist.isEmpty ? null : item.trackArtist;
      case UnifiedLibraryItemType.playlist:
        return null;
    }
  }

  void _onItemTap(BuildContext context, UnifiedLibraryItem item) {
    final controller = ref.read(musicPlayerControllerProvider);
    
    switch (item.type) {
      case UnifiedLibraryItemType.track:
        if (item.localItem != null) {
          controller.playSingle(playableFromLocal(item.localItem!));
        } else if (item.historyItem != null) {
          controller.playSingle(playableFromHistory(item.historyItem!));
        }
        break;
        
      case UnifiedLibraryItemType.artist:
        // Navigate to artist detail or play all artist tracks
        _playArtistTracks(item.trackArtist);
        break;
        
      case UnifiedLibraryItemType.album:
        // Navigate to album detail or play album
        _playAlbumTracks(item.albumName, item.trackArtist);
        break;
        
      case UnifiedLibraryItemType.playlist:
        // Navigate to playlist detail or play playlist
        _playPlaylist(item.id);
        break;
    }
  }

  void _playArtistTracks(String artist) {
    final controller = ref.read(musicPlayerControllerProvider);
    controller.shuffleLibrary(artist: artist);
  }

  void _playAlbumTracks(String album, String artist) {
    // Would need to query library for album tracks
    // For now, show a snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Play album: $album by $artist')),
    );
  }

  void _playPlaylist(String playlistId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Play playlist: $playlistId')),
    );
  }

  Widget _buildLoading(BuildContext context, bool isRound) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: theme.colorScheme.primary,
            strokeWidth: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'Loading library...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error, bool isRound) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isRound ? kWearTotalCircularInset : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.error,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to Load Library',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.invalidate(localLibraryProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section header for the library list that stays visible during scroll.
class _WearSliverSectionHeader extends StatelessWidget {
  const _WearSliverSectionHeader({
    required this.title,
    required this.isRound,
  });

  final String title;
  final bool isRound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        isRound ? kWearTotalCircularInset : 16,
        16,
        isRound ? kWearTotalCircularInset : 16,
        8,
      ),
      sliver: SliverToBoxAdapter(
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}