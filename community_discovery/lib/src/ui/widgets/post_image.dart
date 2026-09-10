import 'package:flutter/material.dart';

import '../../models/community_post.dart';

class PostImage extends StatefulWidget {
  const PostImage({
    super.key,
    required this.post,
    this.height = 178,
    this.fit = BoxFit.cover,
    this.openFullscreenOnTap = false,
  });
  final CommunityPost post;
  final double height;
  final BoxFit fit;
  final bool openFullscreenOnTap;

  @override
  State<PostImage> createState() => _PostImageState();
}

class _PostImageState extends State<PostImage> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.post.allImageUrls;
    final memory = widget.post.imageBytes;
    final count = memory != null && urls.isEmpty ? 1 : urls.length;
    if (count == 0) {
      return SizedBox(height: widget.height, child: const _ImageFallback());
    }
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            itemCount: count,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, index) => GestureDetector(
              onTap: widget.openFullscreenOnTap
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FullScreenImageViewer(
                          post: widget.post,
                          initialPage: index,
                        ),
                      ),
                    )
                  : null,
              child: ColoredBox(
                color: const Color(0xFFE5E7EB),
                child: memory != null && urls.isEmpty
                    ? Image.memory(memory, fit: widget.fit)
                    : Image.network(
                        urls[index],
                        fit: widget.fit,
                        width: double.infinity,
                        height: widget.height,
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                        errorBuilder: (_, _, _) => const _ImageFallback(),
                      ),
              ),
            ),
          ),
          if (count > 1)
            Positioned(
              right: 10,
              top: 10,
              child: _ImageBadge(label: '${_page + 1}/$count'),
            ),
          if (widget.openFullscreenOnTap)
            const Positioned(
              left: 10,
              bottom: 10,
              child: _ImageBadge(label: 'Tap to view full screen'),
            ),
        ],
      ),
    );
  }
}

class FullScreenImageViewer extends StatefulWidget {
  const FullScreenImageViewer({
    super.key,
    required this.post,
    this.initialPage = 0,
  });
  final CommunityPost post;
  final int initialPage;

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late final PageController _pages;
  final Map<int, TransformationController> _transforms = {};
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _pages = PageController(initialPage: _page);
  }

  TransformationController _transform(int index) =>
      _transforms.putIfAbsent(index, TransformationController.new);
  @override
  void dispose() {
    _pages.dispose();
    for (final value in _transforms.values) {
      value.dispose();
    }
    super.dispose();
  }

  void _toggleZoom(int index) {
    final controller = _transform(index);
    controller.value = controller.value.getMaxScaleOnAxis() > 1
        ? Matrix4.identity()
        : (Matrix4.identity()..scaleByDouble(2.5, 2.5, 2.5, 1));
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.post.allImageUrls;
    final memory = widget.post.imageBytes;
    final count = memory != null && urls.isEmpty ? 1 : urls.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_page + 1}/$count'),
        actions: [
          IconButton(
            tooltip: 'Close image viewer',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: count,
        onPageChanged: (value) => setState(() => _page = value),
        itemBuilder: (_, index) => GestureDetector(
          onDoubleTap: () => _toggleZoom(index),
          child: InteractiveViewer(
            transformationController: _transform(index),
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: memory != null && urls.isEmpty
                  ? Image.memory(memory, fit: BoxFit.contain)
                  : Image.network(
                      urls[index],
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const _ImageFallback(),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageBadge extends StatelessWidget {
  const _ImageBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Text(label, style: const TextStyle(color: Colors.white)),
    ),
  );
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
