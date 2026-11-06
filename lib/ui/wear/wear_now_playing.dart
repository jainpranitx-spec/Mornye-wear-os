/// Wear OS Now Playing screen with circular progress and thumb-friendly controls.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/services/playable_media.dart';
import 'package:mornye/ui/wear/wear_layout.dart';

/// The main Wear OS Now Playing screen.
///
/// Features:
/// - Circular track progress ring around album art
/// - Large thumb-friendly Play/Pause/Previous/Next buttons
/// - Auto-scrolling marquee for track/artist names
/// - Ambient mode support (dimmed, simplified UI)
class WearNowPlayingScreen extends ConsumerStatefulWidget {
  const WearNowPlayingScreen({super.key});

  @override
  ConsumerState<WearNowPlayingScreen> createState() => _WearNowPlayingScreenState();
}

class _WearNowPlayingScreenState extends ConsumerState<WearNowPlayingScreen>
    with WidgetsBindingObserver {
  bool _isAmbientMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On Wear OS, ambient mode is signaled via lifecycle changes
    // and platform-specific callbacks. This is a simplified handler.
    if (state == AppLifecycleState.inactive || 
        state == AppLifecycleState.paused) {
      // Could be entering ambient mode
    } else if (state == AppLifecycleState.resumed) {
      // Exiting ambient mode
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaItem = ref.watch(currentMediaItemProvider);
    final playbackState = ref.watch(playbackStateProvider);
    final controller = ref.watch(musicPlayerControllerProvider);
    final theme = Theme.of(context);
    final isRound = context.isWearRound;

    return WearLayoutBuilder(
      builder: (context, safeRect, isRound) {
        return Scaffold(
          backgroundColor: _isAmbientMode 
              ? theme.colorScheme.surface 
              : theme.colorScheme.surface,
          body: mediaItem.when(
            data: (item) => _buildContent(
              context,
              item,
              playbackState.value,
              controller,
              safeRect,
              isRound,
            ),
            loading: () => _buildLoading(context, safeRect, isRound),
            error: (_, __) => _buildError(context, safeRect, isRound),
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    MediaItem? item,
    PlaybackState? state,
    MusicPlayerController controller,
    Rect safeRect,
    bool isRound,
  ) {
    if (item == null) {
      return _buildEmptyState(context, safeRect, isRound);
    }

    final isPlaying = state?.playing ?? false;
    final position = state?.position ?? Duration.zero;
    final duration = item.duration ?? Duration.zero;
    final progress = duration > Duration.zero 
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(isRound ? kWearTotalCircularInset : 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Album art with circular progress ring
            _buildAlbumArtWithProgress(
              context,
              item,
              progress,
              isPlaying,
              safeRect,
              isRound,
            ),
            
            const SizedBox(height: 16),
            
            // Track title with marquee
            _buildTrackTitle(context, item, isRound),
            
            const SizedBox(height: 4),
            
            // Artist name with marquee
            _buildArtistName(context, item, isRound),
            
            const SizedBox(height: 20),
            
            // Playback controls
            _buildPlaybackControls(
              context,
              controller,
              isPlaying,
              isRound,
            ),
            
            const SizedBox(height: 12),
            
            // Time indicators
            _buildTimeIndicators(context, position, duration, isRound),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumArtWithProgress(
    BuildContext context,
    MediaItem item,
    double progress,
    bool isPlaying,
    Rect safeRect,
    bool isRound,
  ) {
    final theme = Theme.of(context);
    final artSize = isRound 
        ? math.min(safeRect.width, safeRect.height) * 0.7
        : math.min(MediaQuery.of(context).size.width, 280.0);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Circular progress ring
        SizedBox(
          width: artSize + 16,
          height: artSize + 16,
          child: WearCircularProgress(
            progress: progress,
            size: artSize + 16,
            strokeWidth: 4.0,
            backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            progressColor: theme.colorScheme.primary,
          ),
        ),
        // Album artwork
        ClipRRect(
          borderRadius: BorderRadius.circular(artSize / 2),
          child: _buildAlbumArt(item, artSize),
        ),
        // Play/pause overlay in center (for quick tap)
        if (_isAmbientMode)
          Container(
            width: artSize,
            height: artSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.3),
            ),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: artSize * 0.3,
            ),
          ),
      ],
    );
  }

  Widget _buildAlbumArt(MediaItem item, double size) {
    final artUri = item.artUri;
    
    if (artUri != null && artUri.isNotEmpty) {
      return Image.network(
        artUri,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholderArt(size),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _buildPlaceholderArt(size);
        },
      );
    }
    
    return _buildPlaceholderArt(size);
  }

  Widget _buildPlaceholderArt(double size) {
    final theme = Theme.of(context);
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

  Widget _buildTrackTitle(
    BuildContext context,
    MediaItem item,
    bool isRound,
  ) {
    return WearMarqueeText(
      text: item.title.isEmpty ? 'Unknown Track' : item.title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: _isAmbientMode 
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)
            : null,
      ),
      maxLines: 1,
      velocity: const Velocity(pixelsPerSecond: 25.0),
    );
  }

  Widget _buildArtistName(
    BuildContext context,
    MediaItem item,
    bool isRound,
  ) {
    final artist = item.artist ?? 'Unknown Artist';
    
    return WearMarqueeText(
      text: artist,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: _isAmbientMode 
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      maxLines: 1,
      velocity: const Velocity(pixelsPerSecond: 25.0),
    );
  }

  Widget _buildPlaybackControls(
    BuildContext context,
    MusicPlayerController controller,
    bool isPlaying,
    bool isRound,
  ) {
    final theme = Theme.of(context);
    final buttonSize = isRound ? 56.0 : 64.0;
    final iconSize = isRound ? 28.0 : 32.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous
        _ControlButton(
          icon: Icons.skip_previous,
          size: buttonSize,
          iconSize: iconSize,
          onPressed: () => controller.previous(),
          tooltip: 'Previous',
        ),
        
        const SizedBox(width: 16),
        
        // Play/Pause (larger)
        _ControlButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          size: buttonSize * 1.3,
          iconSize: iconSize * 1.3,
          isPrimary: true,
          onPressed: () => controller.togglePlayPause(isPlaying),
          tooltip: isPlaying ? 'Pause' : 'Play',
        ),
        
        const SizedBox(width: 16),
        
        // Next
        _ControlButton(
          icon: Icons.skip_next,
          size: buttonSize,
          iconSize: iconSize,
          onPressed: () => controller.next(),
          tooltip: 'Next',
        ),
      ],
    );
  }

  Widget _buildTimeIndicators(
    BuildContext context,
    Duration position,
    Duration duration,
    bool isRound,
  ) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(_formatDuration(position), style: style),
        Text(_formatDuration(duration), style: style),
      ],
    );
  }

  Widget _buildLoading(BuildContext context, Rect safeRect, bool isRound) {
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
            'Loading...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, Rect safeRect, bool isRound) {
    final theme = Theme.of(context);
    return Center(
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
            'Playback Error',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Unable to load playback info',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, Rect safeRect, bool isRound) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_off,
            color: theme.colorScheme.onSurfaceVariant,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Nothing Playing',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Open Mornye on your phone\nto start playback',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// A circular control button optimized for Wear OS touch targets.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.onPressed,
    required this.tooltip,
    this.isPrimary = false,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isPrimary 
            ? theme.colorScheme.primary 
            : theme.colorScheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        elevation: isPrimary ? 4 : 1,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              color: isPrimary 
                  ? theme.colorScheme.onPrimary 
                  : theme.colorScheme.onSurface,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ambient mode variant of the Now Playing screen.
///
/// Shows a simplified, low-power version with just the essential info:
/// - Album art (dimmed)
/// - Track title
/// - Time progress (minimal)
class WearNowPlayingAmbient extends ConsumerWidget {
  const WearNowPlayingAmbient({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(currentMediaItemProvider);
    final playbackState = ref.watch(playbackStateProvider);
    final theme = Theme.of(context);

    return mediaItem.when(
      data: (item) {
        if (item == null) {
          return _buildAmbientEmpty(context);
        }

        final state = playbackState.value;
        final isPlaying = state?.playing ?? false;
        final position = state?.position ?? Duration.zero;
        final duration = item.duration ?? Duration.zero;
        final progress = duration > Duration.zero 
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return WearLayoutBuilder(
          builder: (context, safeRect, isRound) {
            return Container(
              color: Colors.black,
              child: Stack(
                children: [
                  // Dimmed album art background
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.15,
                      child: _buildAmbientAlbumArt(item, safeRect, isRound),
                    ),
                  ),
                  // Foreground content
                  SafeArea(
                    child: Padding(
                      padding: EdgeInsets.all(isRound ? kWearTotalCircularInset : 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Minimal progress ring
                          SizedBox(
                            width: isRound ? safeRect.width * 0.5 : 120,
                            height: isRound ? safeRect.width * 0.5 : 120,
                            child: CustomPaint(
                              painter: _AmbientProgressPainter(
                                progress: progress,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Track title
                          Text(
                            item.title.isEmpty ? 'Unknown' : item.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          // Time
                          Text(
                            '${_formatDuration(position)} / ${_formatDuration(duration)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => _buildAmbientLoading(context),
      error: (_, __) => _buildAmbientError(context),
    );
  }

  Widget _buildAmbientAlbumArt(MediaItem item, Rect safeRect, bool isRound) {
    final size = isRound ? math.min(safeRect.width, safeRect.height) : 200.0;
    final artUri = item.artUri;
    
    if (artUri != null && artUri.isNotEmpty) {
      return Image.network(
        artUri,
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }
    
    return Container(
      width: size,
      height: size,
      color: Colors.grey[800],
      child: const Icon(Icons.music_note, color: Colors.white, size: 64),
    );
  }

  Widget _buildAmbientEmpty(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off, color: Colors.white.withValues(alpha: 0.3), size: 48),
            const SizedBox(height: 8),
            Text(
              'Nothing Playing',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmbientLoading(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: CircularProgressIndicator(
          color: Colors.white.withValues(alpha: 0.5),
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildAmbientError(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Text(
          'Error',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _AmbientProgressPainter extends CustomPainter {
  _AmbientProgressPainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final strokeWidth = 3.0;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    if (progress > 0) {
      final sweepAngle = 2 * math.pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}