import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../services/travel_place_search_service.dart';

class TravelPlacePhoto extends StatelessWidget {
  const TravelPlacePhoto({
    super.key,
    required this.placeName,
    required this.placeSearchService,
    this.knownPhotoName,
    this.width = 72,
    this.height = 72,
    this.borderRadius = 12,
  });

  final String placeName;
  final TravelPlaceSearchService placeSearchService;
  final String? knownPhotoName;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: SizedBox(
      width: width,
      height: height,
      child: FutureBuilder<String?>(
        future: placeSearchService.photoForDestination(
          placeName,
          knownPhotoName: knownPhotoName,
        ),
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url == null || url.isEmpty) return const _PhotoFallback();
          return Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _PhotoFallback(),
          );
        },
      ),
    ),
  );
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.paleBlue,
    child: Icon(Icons.photo_outlined, color: AppColors.primary),
  );
}
