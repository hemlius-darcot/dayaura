import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';

class InlineVideoPlayer extends StatefulWidget {
  final String videoAsset;
  final String? caption;

  const InlineVideoPlayer({
    super.key,
    required this.videoAsset,
    this.caption,
  });

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.asset(widget.videoAsset);
      await _controller.initialize();
      _controller.addListener(() {
        if (mounted) setState(() {});
      });
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullscreenVideoPage(
          controller: _controller,
          caption: widget.caption,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_hasError) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF221616) : const Color(0xFFFDE8E8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.candleRed.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.candleRed),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Video player error: $_errorMessage',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        height: 200,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161C18) : const Color(0xFFF0F4F1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryGreen),
        ),
      );
    }

    final isPlaying = _controller.value.isPlaying;
    final position = _controller.value.position;
    final duration = _controller.value.duration;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF2B3A31) : const Color(0xFFDCE4DF),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video Surface
          GestureDetector(
            onTap: () {
              if (isPlaying) {
                _controller.pause();
              } else {
                _controller.play();
              }
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: _controller.value.aspectRatio > 0
                      ? _controller.value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(_controller),
                ),
                // Big Play/Pause Button Overlay when paused
                if (!isPlaying)
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
              ],
            ),
          ),

          // Video Controls Bar
          Container(
            color: const Color(0xFF151916),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                // Play / Pause Toggle
                IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: () {
                    if (isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                  },
                ),

                // Scrubber Slider
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbColor: AppTheme.primaryGreen,
                      activeTrackColor: AppTheme.primaryGreen,
                      inactiveTrackColor: Colors.white24,
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
                      max: duration.inMilliseconds.toDouble(),
                      onChanged: (val) {
                        _controller.seekTo(Duration(milliseconds: val.toInt()));
                      },
                    ),
                  ),
                ),

                // Time Duration
                Text(
                  '${_formatDuration(position)} / ${_formatDuration(duration)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),

                // Fullscreen Button
                IconButton(
                  icon: const Icon(
                    Icons.fullscreen_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  tooltip: 'Fullscreen',
                  onPressed: () => _openFullscreen(context),
                ),
              ],
            ),
          ),

          // Caption
          if (widget.caption != null && widget.caption!.isNotEmpty)
            Container(
              color: isDark ? const Color(0xFF1E2822) : const Color(0xFFF7FAF8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.videocam_outlined, size: 16, color: AppTheme.primaryGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.caption!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FullscreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;
  final String? caption;

  const _FullscreenVideoPage({
    required this.controller,
    this.caption,
  });

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isPlaying = controller.value.isPlaying;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            // Top Back Button
            Positioned(
              top: 10,
              left: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            // Play/Pause Overlay
            Center(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  });
                },
                child: !isPlaying
                    ? Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
