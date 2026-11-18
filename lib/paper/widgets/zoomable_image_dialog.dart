import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ZoomableImageCard extends StatelessWidget {
  final String assetPath;
  final String? caption;

  const ZoomableImageCard({
    super.key,
    required this.assetPath,
    this.caption,
  });

  void _openLightbox(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close Lightbox',
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, anim1, anim2) {
        return _FullscreenImageLightbox(
          assetPath: assetPath,
          caption: caption,
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openLightbox(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Compact Image Preview with Zoom Badge
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 250,
                      width: double.infinity,
                      color: isDark ? const Color(0xFF0D120E) : const Color(0xFFF1F5F2),
                      child: Image.asset(
                        assetPath,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return _PlaceholderScreenshotView(
                            assetPath: assetPath,
                            isDark: isDark,
                          );
                        },
                      ),
                    ),
                    // Gradient overlay at bottom of image
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.65),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Zoom Badge
                    Positioned(
                      bottom: 8,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in_rounded, size: 15, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'Tap to Zoom',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // Caption
                if (caption != null && caption!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 10.0,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.image_outlined,
                          size: 16,
                          color: AppTheme.primaryGreen,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            caption!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderScreenshotView extends StatelessWidget {
  final String assetPath;
  final bool isDark;

  const _PlaceholderScreenshotView({
    required this.assetPath,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final fileName = assetPath.split('/').last;

    return Container(
      color: isDark ? const Color(0xFF141C16) : const Color(0xFFF0F5F2),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.screenshot_monitor_rounded,
              size: 34,
              color: AppTheme.primaryGreen,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            fileName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ready for Screenshot',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullscreenImageLightbox extends StatefulWidget {
  final String assetPath;
  final String? caption;

  const _FullscreenImageLightbox({
    required this.assetPath,
    this.caption,
  });

  @override
  State<_FullscreenImageLightbox> createState() => _FullscreenImageLightboxState();
}

class _FullscreenImageLightboxState extends State<_FullscreenImageLightbox> {
  final TransformationController _transformController = TransformationController();
  TapDownDetails? _doubleTapDetails;

  void _handleDoubleTap() {
    if (_transformController.value != Matrix4.identity()) {
      _transformController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      // ignore: deprecated_member_use
      _transformController.value = Matrix4.identity()
        // ignore: deprecated_member_use
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        // ignore: deprecated_member_use
        ..scale(2.5);
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            // Interactive Zoom Viewer
            GestureDetector(
              onDoubleTapDown: (details) => _doubleTapDetails = details,
              onDoubleTap: _handleDoubleTap,
              child: Center(
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 0.8,
                  maxScale: 6.0,
                  panEnabled: true,
                  scaleEnabled: true,
                  child: Image.asset(
                    widget.assetPath,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.broken_image_rounded,
                              size: 60,
                              color: AppTheme.candleRed,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.assetPath,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Top Action Bar
            Positioned(
              top: 10,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  // Close Button
                  CircleAvatar(
                    backgroundColor: Colors.black.withValues(alpha: 0.65),
                    radius: 20,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const Spacer(),
                  // Reset Zoom Button
                  CircleAvatar(
                    backgroundColor: Colors.black.withValues(alpha: 0.65),
                    radius: 20,
                    child: IconButton(
                      icon: const Icon(Icons.restart_alt_rounded, color: Colors.white, size: 20),
                      tooltip: 'Reset Zoom',
                      onPressed: () {
                        _transformController.value = Matrix4.identity();
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Caption Bar
            if (widget.caption != null && widget.caption!.isNotEmpty)
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: Text(
                      widget.caption!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
