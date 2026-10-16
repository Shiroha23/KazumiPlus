import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';

class BangumiPosterGrid extends StatelessWidget {
  const BangumiPosterGrid({
    super.key,
    required this.items,
    required this.width,
    required this.showRating,
  });

  final List<BangumiItem> items;
  final double width;
  final bool showRating;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final titleStyle = textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.4,
    );

    double textHeight(String text, TextStyle style) {
      // Measure with nonlinear accessibility scaling.
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout();
      final height = painter.height.ceilToDouble();
      painter.dispose();
      return height;
    }

    final titleHeight = textHeight('番剧\n番剧', titleStyle);
    final metadataHeight = math.max(
      BangumiPosterCard.ratingIconSize,
      textHeight('0.0 0000', textTheme.labelMedium!),
    );
    final columns = math.max(2, (width / 180).floor());
    final cardWidth = (width - (columns - 1) * 12) / columns;

    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 20,
        mainAxisExtent:
            cardWidth / BangumiPosterCard.coverAspectRatio +
            titleHeight +
            metadataHeight +
            BangumiPosterCard.titleSpacing +
            BangumiPosterCard.metadataSpacing +
            6,
      ),
      itemCount: items.length,
      itemBuilder: (_, index) => BangumiPosterCard(
        item: items[index],
        showRating: showRating,
        titleHeight: titleHeight,
        titleStyle: titleStyle,
      ),
    );
  }
}

class BangumiPosterCard extends StatelessWidget {
  const BangumiPosterCard({
    super.key,
    required this.item,
    required this.showRating,
    required this.titleHeight,
    required this.titleStyle,
  });

  static const coverAspectRatio = 0.7;
  static const titleSpacing = 10.0;
  static const metadataSpacing = 4.0;
  static const ratingIconSize = 14.0;

  final BangumiItem item;
  final bool showRating;
  final double titleHeight;
  final TextStyle titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    final year = item.airDate.length >= 4 ? item.airDate.substring(0, 4) : '';
    return Material(
      type: MaterialType.transparency,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.pushNamed('/info/', arguments: item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: coverAspectRatio,
                child: LayoutBuilder(
                  builder: (_, constraints) => NetworkImgLayer(
                    src: item.images['large'] ?? item.images['common'] ?? '',
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    // Reuse the decoded cover while the window is resized.
                    decodeWidth: 512,
                  ),
                ),
              ),
            ),
            const SizedBox(height: titleSpacing),
            SizedBox(
              height: titleHeight,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            const SizedBox(height: metadataSpacing),
            Row(
              children: [
                if (showRating && item.ratingScore > 0) ...[
                  Icon(
                    Icons.star_rounded,
                    size: ratingIconSize,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    item.ratingScore.toStringAsFixed(1),
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    year,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
