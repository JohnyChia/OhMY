import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/community_repository.dart';
import '../models/community_post.dart';
import '../models/completed_trip.dart';
import '../state/community_controller.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({
    super.key,
    required this.controller,
    this.completedTripId,
    this.post,
  }) : assert(
         (completedTripId == null) != (post == null),
         'Provide either a completedTripId for Create or a post for Edit.',
       );

  final CommunityController controller;
  final String? completedTripId;
  final CommunityPost? post;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  final _picker = ImagePicker();
  late Future<List<CompletedTrip>> _trips;
  CompletedTrip? _selectedTrip;
  final List<PostImageUpload> _images = [];
  bool _replacingImages = false;
  bool _publishing = false;
  bool get _isEditing => widget.post != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.post?.title);
    _descriptionController = TextEditingController(
      text: widget.post?.description,
    );
    _trips = _isEditing
        ? Future.value(const <CompletedTrip>[])
        : widget.controller.getEligibleTrips();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining = _isEditing && !_replacingImages ? 6 : 6 - _images.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A post can contain up to 6 pictures.')),
      );
      return;
    }
    final selected = await _picker.pickMultiImage(
      imageQuality: 88,
      maxWidth: 1800,
      limit: remaining,
    );
    if (selected.isEmpty) return;
    final uploads = <PostImageUpload>[];
    for (final image in selected) {
      final bytes = await image.readAsBytes();
      if (bytes.lengthInBytes > 10 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${image.name} is larger than 10 MB.')),
          );
        }
        return;
      }
      final extension = image.name.contains('.')
          ? image.name.split('.').last.toLowerCase()
          : 'jpg';
      if (!{'jpg', 'jpeg', 'png'}.contains(extension)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${image.name}: only JPG, JPEG, and PNG are accepted.',
              ),
            ),
          );
        }
        return;
      }
      uploads.add(PostImageUpload(bytes: bytes, extension: extension));
    }
    setState(() {
      if (_isEditing && !_replacingImages) {
        _images.clear();
        _replacingImages = true;
      }
      _images.addAll(uploads.take(6 - _images.length));
    });
  }

  Future<void> _publish() async {
    final trip = _selectedTrip;
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    if ((!_isEditing && trip == null) ||
        (!_isEditing && _images.isEmpty) ||
        (_isEditing && _replacingImages && _images.isEmpty) ||
        title.length < 3 ||
        description.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add a title, description, picture, and completed trip.',
          ),
        ),
      );
      return;
    }
    setState(() => _publishing = true);
    try {
      if (_isEditing) {
        await widget.controller.updatePost(
          UpdatePostInput(
            postId: widget.post!.id,
            title: title,
            description: description,
            images: _replacingImages ? List.unmodifiable(_images) : null,
            existingImagePaths: widget.post!.imagePaths,
          ),
        );
      } else {
        await widget.controller.createPost(
          CreatePostInput(
            completedTripId: trip!.id,
            title: title,
            description: description,
            images: List.unmodifiable(_images),
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_isEditing ? 'Post could not be updated' : 'Post could not be published'}: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_isEditing ? 'Edit post' : 'Share a completed trip'),
    ),
    body: FutureBuilder<List<CompletedTrip>>(
      future: _trips,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CenteredMessage(
            icon: Icons.error_outline,
            title: 'Trips could not be loaded',
            message: '${snapshot.error}',
          );
        }
        final trips = snapshot.data ?? const [];
        if (!_isEditing && trips.isEmpty) {
          return const _CenteredMessage(
            icon: Icons.flag_outlined,
            title: 'Complete a trip first',
            message:
                'Only completed trips that have not been posted can be shared.',
          );
        }
        if (_selectedTrip == null && !_isEditing) {
          _selectedTrip = trips
              .where((trip) => trip.id == widget.completedTripId)
              .firstOrNull;
          if (_selectedTrip == null) {
            return const _CenteredMessage(
              icon: Icons.lock_clock_outlined,
              title: 'Trip is not available',
              message:
                  'This trip is unfinished, already posted, or does not belong to the signed-in user.',
            );
          }
        }
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (!_isEditing) ...[
              Text(
                '1. Completed trip',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(_selectedTrip!.title),
                  subtitle: Text(
                    '${_selectedTrip!.attractionName}, ${_selectedTrip!.locationName}\nLocation is locked to this completed trip.',
                  ),
                  isThreeLine: true,
                ),
              ),
            ],
            const SizedBox(height: 22),
            Text(
              _isEditing ? 'Pictures' : '2. Add pictures',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 3),
            Text(
              'Select 1–6 JPG or PNG pictures. Swipe left or right to preview.',
            ),
            const SizedBox(height: 8),
            _ImageEditor(
              newImages: _images,
              existingUrls: _replacingImages
                  ? const []
                  : widget.post?.allImageUrls ?? const [],
              onPick: _pickImages,
              onRemove: (index) => setState(() => _images.removeAt(index)),
            ),
            const SizedBox(height: 22),
            Text(
              _isEditing ? 'Title' : '3. Add a title',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              maxLength: 120,
              decoration: const InputDecoration(
                hintText: 'Example: Morning light at Kwai Chai Hong',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isEditing ? 'Description' : '4. Describe your experience',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              minLines: 4,
              maxLines: 7,
              maxLength: 1000,
              decoration: const InputDecoration(
                hintText: 'Share practical tips or a memorable moment…',
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Tags are added automatically'),
                subtitle: const Text(
                  'Tags come only from the completed trip location and attraction, never from your title or description.',
                ),
              ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _publishing ? null : _publish,
              icon: _publishing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.publish),
              label: Text(
                _publishing
                    ? (_isEditing ? 'Saving…' : 'Publishing…')
                    : (_isEditing ? 'Save changes' : 'Publish post'),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your title and description are checked for unsafe, spam-like, meaningless, or location-unrelated text. Publishing is blocked if validation is unavailable.',
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    ),
  );
}

class _ImageEditor extends StatelessWidget {
  const _ImageEditor({
    required this.newImages,
    required this.existingUrls,
    required this.onPick,
    required this.onRemove,
  });

  final List<PostImageUpload> newImages;
  final List<String> existingUrls;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final count = newImages.isNotEmpty ? newImages.length : existingUrls.length;
    if (count == 0) {
      return InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE3ECFA),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFB8CAE7)),
            ),
            child: const _PhotoPrompt(),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => SizedBox(
              width: 270,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: newImages.isNotEmpty
                        ? Image.memory(
                            newImages[index].bytes,
                            fit: BoxFit.cover,
                          )
                        : Image.network(existingUrls[index], fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: Colors.black54,
                      child: newImages.isNotEmpty
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              tooltip: 'Remove picture',
                              onPressed: () => onRemove(index),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 19,
                              ),
                            )
                          : const Icon(
                              Icons.lock_outline,
                              color: Colors.white,
                              size: 18,
                            ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        child: Text(
                          '${index + 1}/$count',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            newImages.isNotEmpty && newImages.length < 6
                ? 'Add more (${newImages.length}/6)'
                : 'Choose a new gallery (maximum 6)',
          ),
        ),
      ],
    );
  }
}

class _PhotoPrompt extends StatelessWidget {
  const _PhotoPrompt();

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.add_photo_alternate_outlined, size: 44),
      SizedBox(height: 8),
      Text('Choose JPG, JPEG, or PNG (maximum 10 MB)'),
    ],
  );
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 60, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
