import 'package:flutter/material.dart';

import '../data/catalog_models.dart';
import '../data/models.dart';
import 'widgets.dart';

/// Cover-first shelves for playlists and albums, with room for two-line titles.
class CatalogCarousel extends StatelessWidget {
  const CatalogCarousel({super.key, required this.items, required this.onOpen});
  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final size = ((MediaQuery.sizeOf(context).width - 52) / 2).clamp(
      144.0,
      200.0,
    );
    final scaler = MediaQuery.textScalerOf(context);
    return SizedBox(
      height: size + 20 + scaler.scale(15) * 2.5 + scaler.scale(12) * 1.4,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          return SizedBox(
            width: size,
            child: InkWell(
              onTap: () => onOpen(item),
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Artwork(
                    Track(
                      id: item.id,
                      title: item.title,
                      imageUrl: item.imageUrl,
                    ),
                    size: size,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
