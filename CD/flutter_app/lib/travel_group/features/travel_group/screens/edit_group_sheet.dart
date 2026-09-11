import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/travel_place_search_service.dart';
import '../utils/profanity_filter.dart';
import '../widgets/travel_group_widgets.dart';
import 'create_group_sheet.dart' show TravellerStepper;

class EditGroupSheet extends StatefulWidget {
  const EditGroupSheet({
    super.key,
    required this.controller,
    this.placeSearchService,
  });

  final TravelGroupController controller;
  final TravelPlaceSearchService? placeSearchService;

  @override
  State<EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends State<EditGroupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _destinationQuery = TextEditingController();
  final _description = TextEditingController();
  late final TravelPlaceSearchService _placeSearch;
  late final bool _ownsPlaceSearch;
  Timer? _searchDebounce;
  List<TravelGroupPlace> _results = const [];
  TravelGroupPlace? _destination;
  String? _searchError;
  late int _maxMembers;
  late JoinMode _joinMode;
  bool _searching = false;
  bool _saving = false;
  bool _destinationChanged = false;

  TravelGroup get _group => widget.controller.activeGroup!;

  @override
  void initState() {
    super.initState();
    _ownsPlaceSearch = widget.placeSearchService == null;
    _placeSearch = widget.placeSearchService ?? TravelPlaceSearchService();
    final group = _group;
    _name.text = group.name;
    _description.text = group.description;
    _destinationQuery.text = group.destination;
    _maxMembers = group.maxMembers;
    _joinMode = group.joinMode;
    _destination = group.destinationLatitude == null
        ? null
        : TravelGroupPlace(
            id: group.destinationPlaceId ?? '',
            name: group.destination,
            address: group.destinationAddress,
            latitude: group.destinationLatitude!,
            longitude: group.destinationLongitude!,
            photoName: group.destinationPhotoName,
          );
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

  int get _minMembers {
    final memberCount = _group.memberCount;
    return memberCount > TravelGroupController.minTravellersPerGroup
        ? memberCount
        : TravelGroupController.minTravellersPerGroup;
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
                      'Edit travel group',
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
                'Existing members are never affected by these changes. Editing is locked once the trip starts.',
                style: TextStyle(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 18),
              TextFormField(
                key: const Key('edit_group_title'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Group title',
                  hintText: 'e.g. Sunset Photography Walk',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Group title is required';
                  }
                  if (ProfanityFilter.hasProfanity(value)) {
                    return 'Group titles cannot contain inappropriate language.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _destinationSearch(),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('edit_group_description'),
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'What kind of trip is this?',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Description is required';
                  }
                  if (ProfanityFilter.hasProfanity(value)) {
                    return 'Group descriptions cannot contain inappropriate language.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text(
                '${_group.memberCount} traveller(s) currently in the group',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 6),
              TravellerStepper(
                value: _maxMembers,
                minValue: _minMembers,
                maxValue: TravelGroupController.maxTravellersPerGroup,
                onChanged: (value) => setState(() => _maxMembers = value),
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
                child: Text(_saving ? 'Saving...' : 'Save changes'),
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
          key: const Key('edit_destination_search'),
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
          validator: (_) => _destinationChanged && _destination == null
              ? 'Select a destination from the results or clear this field'
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
                    key: Key('edit_destination_result_$index'),
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
    final query = value.trim();
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _destination = null;
        _destinationChanged = false;
        _searchError = null;
      });
      return;
    }
    if (_destination == null || query != _destination!.name) {
      setState(() {
        _destination = null;
        _destinationChanged = true;
      });
    }
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
      _destinationChanged = true;
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.controller.editGroup(
        name: _name.text,
        destination: _destinationChanged ? _destination : null,
        description: _description.text,
        maxMembers: _maxMembers,
        joinMode: _joinMode,
      );
      if (mounted) Navigator.pop(context, true);
    } on TravelGroupException catch (error) {
      if (mounted) showTravelGroupMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
