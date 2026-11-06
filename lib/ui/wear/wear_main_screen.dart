/// Wear OS main navigation screen.
///
/// Provides a page view between Now Playing and Library screens,
/// optimized for Wear OS navigation patterns.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/ui/wear/wear_layout.dart';
import 'package:mornye/ui/wear/wear_now_playing.dart';
import 'package:mornye/ui/wear/wear_library.dart';

/// The main Wear OS app screen with page-based navigation.
///
/// Uses a [PageView] for horizontal swipe navigation between:
/// - Page 0: Now Playing (primary screen)
/// - Page 1: Library Browser
class WearMainScreen extends ConsumerStatefulWidget {
  const WearMainScreen({super.key});

  @override
  ConsumerState<WearMainScreen> createState() => _WearMainScreenState();
}

class _WearMainScreenState extends ConsumerState<WearMainScreen> {
  final PageController _pageController = PageController(initialPage: 0);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return WearLayoutBuilder(
      builder: (context, safeRect, isRound) {
        return Scaffold(
          body: Stack(
            children: [
              // Page view for horizontal navigation
              PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: const [
                  WearNowPlayingScreen(),
                  WearLibraryScreen(),
                ],
              ),
              
              // Page indicator dots (only on round screens where space is limited)
              if (isRound)
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: _buildPageIndicator(theme),
                ),
              
              // Quick actions hint (optional)
              if (isRound)
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: _buildPageHint(theme),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPageIndicator(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < 2; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: _currentPage == i ? 16 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: _currentPage == i
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }

  Widget _buildPageHint(ThemeData theme) {
    final hints = ['Now Playing', 'Library'];
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          hints[_currentPage],
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Ambient mode variant of the main screen.
///
/// Shows a simplified, always-on version of the current page.
class WearMainScreenAmbient extends ConsumerWidget {
  const WearMainScreenAmbient({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // In ambient mode, always show Now Playing
    return const WearNowPlayingAmbient();
  }
}