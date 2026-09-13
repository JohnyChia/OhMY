import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/live_trip_location_service.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';
import 'package:flutter_app/user_management/config/travel_preference_options.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/travel_place_search_service.dart';
import '../utils/profanity_filter.dart';

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
  int _maxMembers = TravelGroupController.maxTravellersPerGroup;
  JoinMode _joinMode = JoinMode.open;
  bool _searching = false;
  bool _saving = false;
  String? _tagError;
  String? _submitError;
  final _tagErrorKey = GlobalKey();
  final _submitErrorKey = GlobalKey();

  static const tagOptions = culturalTravelPreferenceOptions;

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
                      'Create Group Trip',
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
                validator: _titleValidator,
              ),
              _destinationSearch(),
              const SizedBox(height: 12),
              _field(
                _description,
                'Description',
                'What kind of trip is this?',
                maxLines: 3,
                fieldKey: const Key('group_description'),
                validator: _descriptionValidator,
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
                        backgroundColor: const Color(0xF2FFFFFF),
                        selectedColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          color: _tags.contains(tag)
                              ? Colors.white
                              : AppColors.secondaryText,
                        ),
                        onSelected: (_) => setState(() {
                          _tags.contains(tag)
                              ? _tags.remove(tag)
                              : _tags.add(tag);
                          if (_tags.isNotEmpty) _tagError = null;
                        }),
                      ),
                    )
                    .toList(),
              ),
              if (_tagError != null) ...[
                const SizedBox(height: 8),
                _InlineFormError(key: _tagErrorKey, message: _tagError!),
              ],
              const SizedBox(height: 16),
              TravellerStepper(
                value: _maxMembers,
                minValue: TravelGroupController.minTravellersPerGroup,
                maxValue: TravelGroupController.maxTravellersPerGroup,
                onChanged: (value) => setState(() => _maxMembers = value),
              ),
              const SizedBox(height: 14),
              SegmentedButton<JoinMode>(
                style: SegmentedButton.styleFrom(
                  backgroundColor: const Color(0xF2FFFFFF),
                  foregroundColor: AppColors.primaryDark,
                  selectedBackgroundColor: AppColors.primary,
                  selectedForegroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.border),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
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
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                _InlineFormError(key: _submitErrorKey, message: _submitError!),
              ],
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
                      child: WauLoadingIndicator(size: 18),
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

  String? _titleValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Group title is required';
    }
    if (ProfanityFilter.hasProfanity(value)) {
      return 'Group titles cannot contain inappropriate language.';
    }
    return null;
  }

  String? _descriptionValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Description is required';
    }
    if (ProfanityFilter.hasProfanity(value)) {
      return 'Group descriptions cannot contain inappropriate language.';
    }
    return null;
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
    Key? fieldKey,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: fieldKey,
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator:
            validator ??
            (value) => value == null || value.trim().isEmpty
                ? '$label is required'
                : null,
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _tagError = null;
      _submitError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    if (_tags.isEmpty) {
      _showInlineError(
        tagError:
            'Select at least one activity preference for group recommendations.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const TravelGroupException(
          'Enable device location to create a group.',
          'location_required',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const TravelGroupException(
          'Allow precise location to create a nearby group.',
          'location_required',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      widget.controller.validateCreatorLocation(
        _destination!,
        GeoCoordinate(position.latitude, position.longitude),
      );
      final group = await widget.controller.createGroup(
        creatorLocation: GeoCoordinate(position.latitude, position.longitude),
        name: _name.text,
        destination: _destination!,
        description: _description.text,
        tags: _tags.toList(),
        maxMembers: _maxMembers,
        joinMode: _joinMode,
      );
      if (mounted) Navigator.pop(context, group);
    } on TravelGroupException catch (error) {
      if (mounted) _showInlineError(submitError: error.message);
    } catch (_) {
      if (mounted) {
        _showInlineError(
          submitError:
              'Could not obtain your current location. Enable precise location and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showInlineError({String? tagError, String? submitError}) {
    setState(() {
      _tagError = tagError;
      _submitError = submitError;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = tagError != null
          ? _tagErrorKey.currentContext
          : _submitErrorKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 220),
          alignment: .45,
        );
      }
    });
  }
}

class _InlineFormError extends StatelessWidget {
  const _InlineFormError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECEA),
        border: Border.all(color: const Color(0xFFF0A39B)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB3261E), size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF8C1D18), fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}

class TravellerStepper extends StatelessWidget {
  const TravellerStepper({
    super.key,
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
  });

  final int value;
  final int minValue;
  final int maxValue;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Maximum travellers',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _StepperButton(
              icon: Icons.remove_rounded,
              onPressed: value > minValue ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 64,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            _StepperButton(
              icon: Icons.add_rounded,
              onPressed: value < maxValue ? () => onChanged(value + 1) : null,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Up to maximum of 4 travellers total',
                style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'You are included as traveller 1.',
          style: TextStyle(fontSize: 10, color: AppColors.secondaryText),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}
