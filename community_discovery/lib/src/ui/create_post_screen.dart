import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/community_repository.dart';
import '../data/community_validation_api.dart';
import '../models/community_post.dart';
import '../models/completed_trip.dart';
import '../state/community_controller.dart';
import 'widgets/community_status_card.dart';

enum PostEditorResult { saved, deleted }

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({
    super.key,
    required this.controller,
    this.completedTrip,
    this.post,
  }) : assert(
         (completedTrip == null) != (post == null),
         'Provide either a completedTrip for Create or a post for Edit.',
       );

  final CommunityController controller;
  final CompletedTrip? completedTrip;
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
  bool _deleting = false;
  final Map<String, _SubmissionFeedback> _fieldFeedback = {};
  _SubmissionFeedback? _submissionFeedback;
  bool get _isEditing => widget.post != null;

  void _clearFeedback(String field) {
    if (_fieldFeedback.containsKey(field) || _submissionFeedback != null) {
      setState(() {
        _fieldFeedback.remove(field);
        _submissionFeedback = null;
      });
    }
  }

  void _showLocalError(String field, String message) {
    setState(() {
      _fieldFeedback[field] = _SubmissionFeedback(
        title: 'Rejected',
        message: message,
        isRejection: true,
      );
      _submissionFeedback = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.post?.title);
    _descriptionController = TextEditingController(
      text: widget.post?.description,
    );
    _trips = Future.value(
      widget.completedTrip == null
          ? const <CompletedTrip>[]
          : [widget.completedTrip!],
    );
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
      _showLocalError('images', 'A post can contain up to 6 pictures.');
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
          _showLocalError('images', '${image.name} is larger than 10 MB.');
        }
        return;
      }
      final extension = image.name.contains('.')
          ? image.name.split('.').last.toLowerCase()
          : 'jpg';
      if (!{'jpg', 'jpeg', 'png'}.contains(extension)) {
        if (mounted) {
          _showLocalError(
            'images',
            '${image.name}: only JPG, JPEG, and PNG are accepted.',
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
      _fieldFeedback.remove('images');
      _submissionFeedback = null;
    });
  }

  Future<void> _publish() async {
    final trip = _selectedTrip;
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final localErrors = <String, String>{};
    if (!_isEditing && trip == null) {
      localErrors['trip'] = 'Choose a completed trip.';
    }
    if (!_isEditing && _images.isEmpty) {
      localErrors['images'] = 'Select at least one picture.';
    } else if (_isEditing && _replacingImages && _images.isEmpty) {
      localErrors['images'] = 'Select at least one replacement picture.';
    }
    if (title.length < 3 || title.length > 120) {
      localErrors['title'] = 'Title must be between 3 and 120 characters.';
    }
    if (description.length < 10 || description.length > 1000) {
      localErrors['description'] =
          'Description must be between 10 and 1000 characters.';
    }
    if (localErrors.isNotEmpty) {
      setState(() {
        _fieldFeedback
          ..clear()
          ..addEntries(
            localErrors.entries.map(
              (entry) => MapEntry(
                entry.key,
                _SubmissionFeedback(
                  title: 'Rejected',
                  message: entry.value,
                  isRejection: true,
                ),
              ),
            ),
          );
        _submissionFeedback = null;
      });
      return;
    }
    setState(() {
      _publishing = true;
      _fieldFeedback.clear();
      _submissionFeedback = null;
    });
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
            historyEntryId: trip!.id,
            title: title,
            description: description,
            images: List.unmodifiable(_images),
          ),
        );
      }
      if (mounted) Navigator.pop(context, PostEditorResult.saved);
    } on CommunityValidationException catch (error) {
      if (mounted) {
        setState(() {
          _fieldFeedback.clear();
          for (final entry in error.fieldErrors.entries) {
            if (const {
              'trip',
              'images',
              'title',
              'description',
            }.contains(entry.key)) {
              _fieldFeedback[entry.key] = _SubmissionFeedback(
                title: 'Rejected',
                message: entry.value,
                isRejection: true,
              );
            }
          }
          _submissionFeedback = _fieldFeedback.isEmpty
              ? _SubmissionFeedback(
                  title: 'Rejected',
                  message: error.reason,
                  details: error.fieldErrors.values.toList(growable: false),
                  isRejection: true,
                )
              : null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _fieldFeedback.clear();
          _submissionFeedback = const _SubmissionFeedback(
            title: 'Could not check post',
            message:
                'The validation service is unavailable. Check your connection and try again.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _deletePost() async {
    final post = widget.post;
    if (post == null || _deleting) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete permanently?'),
            content: const Text(
              'This post and all of its comments will be deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.controller.deletePost(post.id);
      if (mounted) Navigator.pop(context, PostEditorResult.deleted);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submissionFeedback = _SubmissionFeedback(
            title: 'Post not deleted',
            message: error
                .toString()
                .replaceFirst('Bad state: ', '')
                .replaceFirst('Exception: ', ''),
            isRejection: true,
          );
        });
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_isEditing ? 'Edit post' : 'Share a completed trip'),
      actions: [
        if (_isEditing)
          IconButton(
            tooltip: 'Delete post',
            onPressed: _publishing || _deleting ? null : _deletePost,
            icon: _deleting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
          ),
      ],
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
              .where((trip) => trip.id == widget.completedTrip?.id)
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
                    '${_selectedTrip!.locationName}\nLocation is locked to your Travel History.',
                  ),
                  isThreeLine: true,
                ),
              ),
              if (_fieldFeedback['trip'] case final feedback?) ...[
                const SizedBox(height: 8),
                _FeedbackCard(feedback: feedback),
              ],
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
              onRemove: (index) => setState(() {
                _images.removeAt(index);
                _fieldFeedback.remove('images');
                _submissionFeedback = null;
              }),
            ),
            if (_fieldFeedback['images'] case final feedback?) ...[
              const SizedBox(height: 8),
              _FeedbackCard(feedback: feedback),
            ],
            const SizedBox(height: 22),
            Text(
              _isEditing ? 'Title' : '3. Add a title',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              onChanged: (_) => _clearFeedback('title'),
              maxLength: 120,
              decoration: InputDecoration(
                hintText: 'Example: Morning light at Kwai Chai Hong',
                errorText: _fieldFeedback['title']?.inlineMessage,
                errorMaxLines: 4,
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
              onChanged: (_) => _clearFeedback('description'),
              minLines: 4,
              maxLines: 7,
              maxLength: 1000,
              decoration: InputDecoration(
                hintText: 'Share practical tips or a memorable moment…',
                errorText: _fieldFeedback['description']?.inlineMessage,
                errorMaxLines: 4,
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
            if (_submissionFeedback case final feedback?) ...[
              const SizedBox(height: 14),
              _FeedbackCard(feedback: feedback),
            ],
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _publishing || _deleting ? null : _publish,
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

class _SubmissionFeedback {
  const _SubmissionFeedback({
    required this.title,
    required this.message,
    this.details = const <String>[],
    this.isRejection = false,
  });

  final String title;
  final String message;
  final List<String> details;
  final bool isRejection;

  String get inlineMessage => [
    message,
    ...details,
  ].where((value) => value.trim().isNotEmpty).join('\n');
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback});

  final _SubmissionFeedback feedback;

  @override
  Widget build(BuildContext context) => CommunityStatusCard(
    title: feedback.title,
    message: feedback.message,
    details: feedback.details,
    isError: feedback.isRejection,
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
