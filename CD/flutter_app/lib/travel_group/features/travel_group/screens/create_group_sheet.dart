import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/travel_place_search_service.dart';
import '../widgets/travel_group_widgets.dart';

class CreateGroupSheet extends StatefulWidget {
  const CreateGroupSheet({
    super.key,
    required this.controller,
    this.placeSearchService,
  });

  final TravelGroupController controller;
  final TravelPlaceSearchService? placeSearchService;

  @override
  State<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<CreateGroupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _destinationQuery = TextEditingController();
  final _description = TextEditingController();
  final _tags = <String>{};
  late final TravelPlaceSearchService _placeSearch;
  late final bool _ownsPlaceSearch;
  Timer? _searchDebounce;
  List<TravelGroupPlace> _results = const [];
  TravelGroupPlace? _destination;
  String? _searchError;
  int _maxMembers = 6;
  JoinMode _joinMode = JoinMode.open;
  bool _searching = false;
  bool _saving = false;

  static const tagOptions = [
    'Food',
    'Cultural',
    'Budget',
    'Nature',
    'Casual',
    'Heritage',
    'Photography',
  ];

  @override
  void initState() {
    super.initState();
    _ownsPlaceSearch = widget.placeSearchService == null;
    _placeSearch = widget.placeSearchService ?? TravelPlaceSearchService();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _name.dispose();
    _destinationQuery.dispose();
    _description.dispose();
    if (_ownsPlaceSearch) _placeSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .94,
        minChildSize: .68,
        maxChildSize: .97,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Create Travel Group',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Text(
                'Choose where the group is going. You can set a fair meetup point after travellers join.',
                style: TextStyle(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 18),
              _field(
                _name,
                'Group title',
                'e.g. Sunset Photography Walk',
                fieldKey: const Key('group_title'),
              ),
              _destinationSearch(),
              const SizedBox(height: 12),
              _field(
                _description,
                'Description',
                'What kind of trip is this?',
                maxLines: 3,
                fieldKey: const Key('group_description'),
              ),
              const SizedBox(height: 4),
              const Text(
                'Activity tags',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: tagOptions
                    .map(
                      (tag) => FilterChip(
                        label: Text(tag),
                        selected: _tags.contains(tag),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          color: _tags.contains(tag)
                              ? Colors.white
                              : AppColors.secondaryText,
                        ),
                        onSelected: (_) => setState(
                          () => _tags.contains(tag)
                              ? _tags.remove(tag)
                              : _tags.add(tag),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _maxMembers,
                decoration: const InputDecoration(
                  labelText: 'Maximum travellers',
                ),
                items: [2, 3, 4, 5, 6, 8]
                    .map(
                      (size) => DropdownMenuItem(
                        value: size,
                        child: Text('$size travellers'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _maxMembers = value ?? 6),
              ),
              const SizedBox(height: 14),
              SegmentedButton<JoinMode>(
                segments: const [
                  ButtonSegment(
                    value: JoinMode.open,
                    label: Text('Open group'),
                  ),
                  ButtonSegment(
                    value: JoinMode.request,
                    label: Text('Request approval'),
                  ),
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

  Widget _destinationSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: const Key('destination_search'),
          controller: _destinationQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Search destination',
            hintText: 'Search places or attractions',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _destination != null
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                  )
                : null,
          ),
          onChanged: _queueSearch,
          onFieldSubmitted: _search,
          validator: (_) => _destination == null
              ? 'Select a destination from the results'
              : null,
        ),
        if (_searchError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _searchError!,
              style: const TextStyle(fontSize: 11, color: Colors.red),
            ),
          ),
        if (_results.isNotEmpty)
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: AppColors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < _results.length; index++) ...[
                  ListTile(
                    key: Key('destination_result_$index'),
                    dense: true,
                    leading: const Icon(
                      Icons.place_outlined,
                      color: AppColors.primary,
                    ),
                    title: Text(_results[index].name),
                    subtitle: Text(
                      _results[index].address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectDestination(_results[index]),
                  ),
                  if (index < _results.length - 1)
                    const Divider(height: 1, indent: 52),
                ],
              ],
            ),
          ),
      ],
    );
  }

  void _queueSearch(String value) {
    if (_destination != null && value != _destination!.name) {
      setState(() => _destination = null);
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _search(value);
    });
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.length < 2) {
      if (mounted) setState(() => _results = const []);
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await _placeSearch.search(query);
      if (!mounted || _destinationQuery.text.trim() != query) return;
      setState(() => _results = results);
    } catch (_) {
      if (mounted) {
        setState(() => _searchError = 'Could not search places. Try again.');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectDestination(TravelGroupPlace place) async {
    setState(() {
      _destination = place;
      _destinationQuery.text = place.name;
      _results = const [];
      _searching = true;
      _searchError = null;
    });
    try {
      final detailed = place.photoName == null
          ? await _placeSearch.loadDetails(place)
          : place;
      if (mounted) setState(() => _destination = detailed);
    } catch (_) {
      // A selected place remains valid when its optional photo cannot load.
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
    Key? fieldKey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: fieldKey,
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
        destination: _destination!,
        description: _description.text,
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
