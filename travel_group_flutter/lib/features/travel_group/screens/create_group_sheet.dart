import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../widgets/travel_group_widgets.dart';

class CreateGroupSheet extends StatefulWidget {
  const CreateGroupSheet({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  State<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<CreateGroupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _destination = TextEditingController();
  final _description = TextEditingController();
  final _meetup = TextEditingController();
  final _tags = <String>{};
  int _maxMembers = 6;
  JoinMode _joinMode = JoinMode.open;
  bool _saving = false;

  static const tagOptions = [
    'Food',
    'Cultural',
    'Budget',
    'Nature',
    'Casual',
    'Heritage',
    'Photography'
  ];

  @override
  void dispose() {
    _name.dispose();
    _destination.dispose();
    _description.dispose();
    _meetup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .92,
        minChildSize: .65,
        maxChildSize: .96,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('Create Travel Group',
                          style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ],
              ),
              const Text(
                  'Start an impromptu nearby lobby. You can build the itinerary together.'),
              const SizedBox(height: 18),
              _field(_name, 'Group name', 'e.g. Petaling Street Food Hunt'),
              _field(_destination, 'Destination', 'e.g. Petaling Street'),
              _field(_description, 'Description', 'What kind of trip is this?',
                  maxLines: 3),
              _field(_meetup, 'Meetup point', 'A clear public landmark'),
              const SizedBox(height: 8),
              const Text('Activity tags',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: tagOptions
                    .map((tag) => AppPill(
                          tag,
                          selected: _tags.contains(tag),
                          onTap: () => setState(() => _tags.contains(tag)
                              ? _tags.remove(tag)
                              : _tags.add(tag)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _maxMembers,
                decoration:
                    const InputDecoration(labelText: 'Maximum travellers'),
                items: [2, 3, 4, 5]
                    .map((size) => DropdownMenuItem(
                        value: size, child: Text('$size travellers')))
                    .toList(),
                onChanged: (value) => setState(() => _maxMembers = value ?? 5),
              ),
              const SizedBox(height: 14),
              SegmentedButton<JoinMode>(
                segments: const [
                  ButtonSegment(
                      value: JoinMode.open, label: Text('Open group')),
                  ButtonSegment(
                      value: JoinMode.request, label: Text('Request approval')),
                ],
                selected: {_joinMode},
                onSelectionChanged: (value) =>
                    setState(() => _joinMode = value.first),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Creating...' : 'Create group'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, String hint,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: (value) =>
            value == null || value.trim().isEmpty ? '$label is required' : null,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final group = await widget.controller.createGroup(
        name: _name.text,
        destination: _destination.text,
        description: _description.text,
        meetupPoint: _meetup.text,
        tags: _tags.toList(),
        maxMembers: _maxMembers,
        joinMode: _joinMode,
      );
      if (mounted) Navigator.pop(context, group);
    } on TravelGroupException catch (error) {
      if (mounted) showTravelGroupMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
