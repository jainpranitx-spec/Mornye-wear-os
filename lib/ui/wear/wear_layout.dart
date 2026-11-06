/// Wear OS layout utilities for circular displays.
///
/// Provides helpers to inset content away from round screen edges and
/// a [WearLayoutBuilder] that exposes the safe drawing rect for circular screens.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The safe inset for circular Wear OS screens.
///
/// On round watches, content near the edges gets clipped. This constant
/// provides a comfortable margin (in logical pixels) to keep UI elements
/// fully visible on all Wear OS devices.
const double kWearCircularInset = 16.0;

/// Additional inset for the bezel/action area on devices with rotating bezels.
const double kWearBezelInset = 8.0;

/// Total safe inset for circular screens (content + bezel).
const double kWearTotalCircularInset = kWearCircularInset + kWearBezelInset;

/// Builder that provides the safe drawing rectangle for Wear OS screens.
///
/// On circular screens, returns an inset rect that avoids the curved edges.
/// On rectangular screens, returns the full constraints rect.
///
/// Usage:
/// ```dart
/// WearLayoutBuilder(
///   builder: (context, safeRect, isRound) {
///     return Center(
///       child: Container(
///         width: safeRect.width,
///         height: safeRect.height,
///         child: MyCircularContent(),
///       ),
///     );
///   },
/// )
/// ```
class WearLayoutBuilder extends StatelessWidget {
  const WearLayoutBuilder({
    super.key,
    required this.builder,
    this.circularInset = kWearTotalCircularInset,
  });

  final Widget Function(
    BuildContext context,
    Rect safeRect,
    bool isRound,
  ) builder;

  /// Inset to apply on circular screens. Defaults to [kWearTotalCircularInset].
  final double circularInset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isRound = _isRoundScreen(context);
        final safeRect = isRound
            ? Rect.fromLTWH(
                circularInset,
                circularInset,
                constraints.maxWidth - 2 * circularInset,
                constraints.maxHeight - 2 * circularInset,
              )
            : Rect.fromLTWH(
                0,
                0,
                constraints.maxWidth,
                constraints.maxHeight,
              );

        return builder(context, safeRect, isRound);
      },
    );
  }

  /// Detects if the current screen is round.
  ///
  /// Uses [MediaQuery] padding and display features to determine roundness.
  static bool _isRoundScreen(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    
    // Check display features for cutouts/notches that indicate round screens
    final displayFeatures = mediaQuery.displayFeatures;
    for (final feature in displayFeatures) {
      if (feature is DisplayFeature && 
          (feature.type == DisplayFeatureType.cutout || 
           feature.type == DisplayFeatureType.fold)) {
        return true;
      }
    }

    // Fallback: check if padding is asymmetrical (common on round watches)
    final padding = mediaQuery.padding;
    if (padding.top > 0 && padding.bottom > 0 && 
        padding.left > 0 && padding.right > 0) {
      // Heuristic: round watches often have similar padding on all sides
      final avgHorizontal = (padding.left + padding.right) / 2;
      final avgVertical = (padding.top + padding.bottom) / 2;
      if ((avgHorizontal - avgVertical).abs() < 8.0) {
        return true;
      }
    }

    // Check device pixel ratio and common watch resolutions
    final size = mediaQuery.size;
    if (size.width == size.height && size.width <= 500) {
      return true;
    }

    return false;
  }
}

/// A widget that insets its child for circular Wear OS screens.
///
/// Wraps the child in padding that adapts to round vs rectangular displays.
/// Use this for full-screen content that needs to avoid curved edges.
class WearSafeArea extends StatelessWidget {
  const WearSafeArea({
    super.key,
    required this.child,
    this.circularInset = kWearTotalCircularInset,
    this.rectangularPadding = EdgeInsets.zero,
  });

  final Widget child;
  final double circularInset;
  final EdgeInsets rectangularPadding;

  @override
  Widget build(BuildContext context) {
    return WearLayoutBuilder(
      circularInset: circularInset,
      builder: (context, safeRect, isRound) {
        if (isRound) {
          return Padding(
            padding: EdgeInsets.all(circularInset),
            child: child,
          );
        }
        return Padding(
          padding: rectangularPadding,
          child: child,
        );
      },
    );
  }
}

/// A circular progress indicator sized for Wear OS.
///
/// Provides a stroke-width-appropriate circular progress that works well
/// as a track progress ring around album art or as a standalone indicator.
class WearCircularProgress extends StatelessWidget {
  const WearCircularProgress({
    super.key,
    required this.progress,
    this.size = 200.0,
    this.strokeWidth = 6.0,
    this.backgroundColor,
    this.progressColor,
    this.strokeCap = StrokeCap.round,
  });

  /// Progress value from 0.0 to 1.0.
  final double progress;

  /// Diameter of the progress circle.
  final double size;

  /// Thickness of the progress ring.
  final double strokeWidth;

  /// Color of the background track.
  final Color? backgroundColor;

  /// Color of the progress arc.
  final Color? progressColor;

  /// Cap style for the progress arc ends.
  final StrokeCap strokeCap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final fgColor = progressColor ?? theme.colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CircularProgressPainter(
          progress: progress.clamp(0.0, 1.0),
          strokeWidth: strokeWidth,
          backgroundColor: bgColor,
          progressColor: fgColor,
          strokeCap: strokeCap,
        ),
      ),
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  _CircularProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeCap,
  });

  final double progress;
  final double strokeWidth;
  final Color backgroundColor;
  final Color progressColor;
  final StrokeCap strokeCap;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background track
    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = strokeCap
      ..isAntiAlias = true;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    if (progress > 0) {
      final fgPaint = Paint()
        ..color = progressColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = strokeCap
        ..isAntiAlias = true;

      final sweepAngle = 2 * math.pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, // Start at top (12 o'clock)
        sweepAngle,
        false,
        fgPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.strokeCap != strokeCap;
  }
}

/// A text widget that marquees horizontally when content overflows.
///
/// Designed for Wear OS where screen width is limited. Automatically
/// starts scrolling when text exceeds [maxLines] or available width.
class WearMarqueeText extends StatefulWidget {
  const WearMarqueeText({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign = TextAlign.center,
    this.velocity = const Velocity(pixelsPerSecond: 30.0),
    this.pauseDuration = const Duration(seconds: 2),
    this.startDelay = const Duration(seconds: 1),
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;
  final Velocity velocity;
  final Duration pauseDuration;
  final Duration startDelay;

  @override
  State<WearMarqueeText> createState() => _WearMarqueeTextState();
}

class _WearMarqueeTextState extends State<WearMarqueeText>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final AnimationController _animationController;
  bool _needsScrolling = false;
  double _textWidth = 0;
  double _viewportWidth = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    WidgetsBinding.instance.addPostFrameCallback(_measureText);
  }

  void _measureText(_) {
    if (!mounted) return;
    final renderObject = context.findRenderObject() as RenderBox?;
    if (renderObject == null) return;

    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: Directionality.of(context),
      maxLines: widget.maxLines,
    )..layout(minWidth: 0, maxWidth: double.infinity);

    final viewportWidth = renderObject.size.width;
    final textWidth = textPainter.width;

    setState(() {
      _textWidth = textWidth;
      _viewportWidth = viewportWidth;
      _needsScrolling = textWidth > viewportWidth;
    });

    if (_needsScrolling) {
      _startMarquee();
    }
  }

  void _startMarquee() async {
    await Future.delayed(widget.startDelay);
    if (!mounted || !_needsScrolling) return;

    while (mounted && _needsScrolling) {
      // Scroll to end
      await _animateTo(_textWidth - _viewportWidth);
      await Future.delayed(widget.pauseDuration);
      if (!mounted || !_needsScrolling) break;

      // Scroll back to start
      await _animateTo(0);
      await Future.delayed(widget.pauseDuration);
    }
  }

  Future<void> _animateTo(double offset) async {
    if (!mounted) return;
    await _scrollController.animateTo(
      offset,
      duration: Duration(
        milliseconds: ((offset - _scrollController.offset).abs() / 
            widget.velocity.pixelsPerSecond * 1000).round(),
      ),
      curve: Curves.linear,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScrolling) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        textAlign: widget.textAlign,
      );
    }

    return SizedBox(
      width: _viewportWidth,
      child: ListView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        child: Text(
          widget.text,
          style: widget.style,
          maxLines: widget.maxLines,
          textAlign: widget.textAlign,
        ),
      ),
    );
  }
}

/// A responsive column that adapts spacing for circular screens.
///
/// Reduces vertical spacing on round watches to fit more content
/// within the safe circular area.
class WearAdaptiveColumn extends StatelessWidget {
  const WearAdaptiveColumn({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.circularSpacing = 8.0,
    this.rectangularSpacing = 16.0,
  });

  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final double circularSpacing;
  final double rectangularSpacing;

  @override
  Widget build(BuildContext context) {
    return WearLayoutBuilder(
      builder: (context, safeRect, isRound) {
        final spacing = isRound ? circularSpacing : rectangularSpacing;
        return Column(
          mainAxisAlignment: mainAxisAlignment,
          crossAxisAlignment: crossAxisAlignment,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1) SizedBox(height: spacing),
            ],
          ],
        );
      },
    );
  }
}

/// Extension on [BuildContext] for Wear OS utilities.
extension WearContextExtensions on BuildContext {
  /// Whether the current screen is a round Wear OS display.
  bool get isWearRound => WearLayoutBuilder._isRoundScreen(this);

  /// Safe inset for circular screens.
  double get wearCircularInset => isWearRound ? kWearTotalCircularInset : 0.0;

  /// Safe drawing rect for the current screen.
  Rect get wearSafeRect {
    final mediaQuery = MediaQuery.of(this);
    final constraints = BoxConstraints(
      maxWidth: mediaQuery.size.width,
      maxHeight: mediaQuery.size.height,
    );
    if (isWearRound) {
      return Rect.fromLTWH(
        kWearTotalCircularInset,
        kWearTotalCircularInset,
        constraints.maxWidth - 2 * kWearTotalCircularInset,
        constraints.maxHeight - 2 * kWearTotalCircularInset,
      );
    }
    return Rect.fromLTWH(0, 0, constraints.maxWidth, constraints.maxHeight);
  }
}