import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/community_repository.dart';
import '../models/completed_trip.dart';
import '../state/community_controller.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, required this.controller});

  final CommunityController controller;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();
  late Future<List<CompletedTrip>> _trips;
  CompletedTrip? _selectedTrip;
  Uint8List? _imageBytes;
  String _imageExtension = 'jpg';
  final Set<int> _tagIds = {};
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _trips = widget.controller.getEligibleTrips();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (bytes.lengthInBytes > 8 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select an image smaller than 8 MB.'),
          ),
        );
      }
      return;
    }
    final extension = image.name.contains('.')
        ? image.name.split('.').last.toLowerCase()
        : 'jpg';
    setState(() {
      _imageBytes = bytes;
      _imageExtension = {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)
          ? extension
          : 'jpg';
    });
  }

  Future<void> _publish() async {
    final trip = _selectedTrip;
    final image = _imageBytes;
    final description = _descriptionController.text.trim();
    if (trip == null ||
        image == null ||
        description.isEmpty ||
        _tagIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select a completed trip, picture, description, and at least one tag.',
          ),
        ),
      );
      return;
    }
    setState(() => _publishing = true);
    try {
      await widget.controller.createPost(
        CreatePostInput(
          completedTripId: trip.id,
          description: description,
          tagIds: _tagIds.toList(),
          imageBytes: image,
          imageExtension: _imageExtension,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Post could not be published: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Share a completed trip')),
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
        if (trips.isEmpty) {
          return const _CenteredMessage(
            icon: Icons.flag_outlined,
            title: 'Complete a trip first',
            message:
                'Only completed trips that have not been posted can be shared.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              '1. Select your completed trip',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<CompletedTrip>(
              initialValue: _selectedTrip,
              hint: const Text('Choose a completed trip'),
              items: trips
                  .map(
                    (trip) => DropdownMenuItem(
                      value: trip,
                      child: Text(trip.title, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (trip) => setState(() => _selectedTrip = trip),
            ),
            if (_selectedTrip case final trip?) ...[
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(trip.attractionName),
                  subtitle: Text(
                    '${trip.locationName}\nLocation comes from your completed trip.',
                  ),
                  isThreeLine: true,
                ),
              ),
            ],
            const SizedBox(height: 22),
            Text(
              '2. Add one picture',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                height: 220,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFE3ECFA),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFB8CAE7)),
                ),
                child: _imageBytes == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 52),
                          SizedBox(height: 8),
                          Text('Choose from gallery (maximum 8 MB)'),
                        ],
                      )
                    : Image.memory(
                        _imageBytes!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              '3. Describe your experience',
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
            Text(
              '4. Add discovery tags',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: widget.controller.tags
                  .map(
                    (tag) => FilterChip(
                      label: Text(tag.name),
                      selected: _tagIds.contains(tag.id),
                      onSelected: (selected) => setState(
                        () => selected
                            ? _tagIds.add(tag.id)
                            : _tagIds.remove(tag.id),
                      ),
                    ),
                  )
                  .toList(),
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
              label: Text(_publishing ? 'Publishing…' : 'Publish post'),
            ),
          ],
        );
      },
    ),
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
