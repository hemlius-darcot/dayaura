import 'package:flutter/material.dart';
import '../models/document_model.dart';
import '../theme/app_theme.dart';
import 'inline_video_player.dart';
import 'zoomable_image_dialog.dart';

class JournalBlockView extends StatelessWidget {
  final PaperBlock block;

  const JournalBlockView({
    super.key,
    required this.block,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    switch (block.type) {
      case BlockType.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
          child: Text(
            block.text,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              height: 1.35,
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            ),
            softWrap: true,
          ),
        );

      case BlockType.subheading:
        return Padding(
          padding: const EdgeInsets.only(top: 14.0, bottom: 6.0),
          child: Text(
            block.text,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
            ),
            softWrap: true,
          ),
        );

      case BlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.0),
          child: Text(
            block.text,
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              letterSpacing: 0.1,
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            ),
            softWrap: true,
          ),
        );

      case BlockType.bullet:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '•  ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.primaryGreen : const Color(0xFF16A34A),
                ),
              ),
              Expanded(
                child: Text(
                  block.text,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.55,
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          ),
        );

      case BlockType.step:
        final num = block.stepNumber ?? 1;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.subtitle != null && block.subtitle!.isNotEmpty)
                Text(
                  '$num. ${block.subtitle!}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                  ),
                  softWrap: true,
                ),
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  block.text,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.55,
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          ),
        );

      case BlockType.callout:
        Color boxColor;
        Color borderColor;
        Color iconColor;
        IconData icon;
        String defaultLabel;

        switch (block.calloutType) {
          case CalloutType.warning:
            boxColor = AppTheme.candleRed.withValues(alpha: isDark ? 0.12 : 0.08);
            borderColor = AppTheme.candleRed.withValues(alpha: 0.35);
            iconColor = AppTheme.candleRed;
            icon = Icons.warning_amber_rounded;
            defaultLabel = 'Important Note';
            break;
          case CalloutType.keyMetric:
            boxColor = AppTheme.candleYellow.withValues(alpha: isDark ? 0.12 : 0.08);
            borderColor = AppTheme.candleYellow.withValues(alpha: 0.45);
            iconColor = AppTheme.candleYellow;
            icon = Icons.auto_graph_rounded;
            defaultLabel = 'Metric Rule';
            break;
          case CalloutType.info:
            boxColor = AppTheme.infoBlue.withValues(alpha: isDark ? 0.12 : 0.08);
            borderColor = AppTheme.infoBlue.withValues(alpha: 0.4);
            iconColor = AppTheme.infoBlue;
            icon = Icons.info_outline_rounded;
            defaultLabel = 'Note';
            break;
          case CalloutType.tip:
            boxColor = AppTheme.primaryGreen.withValues(alpha: isDark ? 0.12 : 0.08);
            borderColor = AppTheme.primaryGreen.withValues(alpha: 0.35);
            iconColor = AppTheme.primaryGreen;
            icon = Icons.lightbulb_outline_rounded;
            defaultLabel = 'Note';
            break;
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10.0),
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      block.subtitle ?? defaultLabel,
                      style: TextStyle(
                        color: iconColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                      softWrap: true,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      block.text,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                      ),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case BlockType.image:
        return ZoomableImageCard(
          assetPath: block.assetPath ?? '',
          caption: block.caption,
        );

      case BlockType.video:
        return InlineVideoPlayer(
          videoAsset: block.assetPath ?? 'assets/videos/task_creation_tutorial.mp4',
          caption: block.caption,
        );

      case BlockType.quote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          padding: const EdgeInsets.only(left: 14.0, top: 4.0, bottom: 4.0),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isDark ? AppTheme.primaryGreen : const Color(0xFF22C55E),
                width: 3.5,
              ),
            ),
          ),
          child: Text(
            block.text,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.55,
              fontStyle: FontStyle.italic,
              color: isDark ? const Color(0xFFD1D5DB) : const Color(0xFF374151),
            ),
            softWrap: true,
          ),
        );
    }
  }
}
