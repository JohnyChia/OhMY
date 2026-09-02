import 'package:flutter/material.dart';

import '../../models/community_post.dart';

class PostImage extends StatelessWidget {
  const PostImage({super.key, required this.post, this.height = 230});

  final CommunityPost post;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bytes = post.imageBytes;
    final url = post.imageUrl;
    Widget image;
    if (bytes != null) {
      image = Image.memory(bytes, fit: BoxFit.cover, width: double.infinity);
    } else if (url != null && url.isNotEmpty) {
      image = Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => const _ImageFallback(),
      );
    } else {
      image = const _ImageFallback();
    }
    return SizedBox(height: height, width: double.infinity, child: image);
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFE3ECFA),
    child: Center(
      child: Icon(
        Icons.landscape_outlined,
        size: 56,
        color: Colors.blue.shade300,
      ),
    ),
  );
}
