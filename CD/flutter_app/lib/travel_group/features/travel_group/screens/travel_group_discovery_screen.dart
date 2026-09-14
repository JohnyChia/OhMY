import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/travel_place_search_service.dart';
import '../widgets/travel_group_scaffold.dart';
import '../widgets/travel_group_widgets.dart';
import 'create_group_sheet.dart';
import 'group_details_screen.dart';
import 'group_lobby_screen.dart';
import 'verification_required_screen.dart';

class TravelGroupDiscoveryScreen extends StatefulWidget {
  const TravelGroupDiscoveryScreen({
    super.key,
    required this.controller,
    this.placeSearchService,
  });

  final TravelGroupController controller;
  final TravelPlaceSearchService? placeSearchService;

  @override
  State<TravelGroupDiscoveryScreen> createState() =>
      _TravelGroupDiscoveryScreenState();
}

class _TravelGroupDiscoveryScreenState
    extends State<TravelGroupDiscoveryScreen> {
  late final TravelPlaceSearchService _placeSearch;
  late final bool _ownsPlaceSearch;
  final Map<String, Future<String?>> _photoFutures = {};
  TravelGroupController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ownsPlaceSearch = widget.placeSearchService == null;
    _placeSearch = widget.placeSearchService ?? TravelPlaceSearchService();
    controller.loadGroups();
    _resolveDefaultArea();
  }

  Future<void> _resolveDefaultArea() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final area = await _placeSearch.areaForCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      await controller.setArea(
        area,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // Groups keep their repository distances if location is unavailable.
    }
  }

  @override
  void dispose() {
    if (_ownsPlaceSearch) _placeSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TravelGroupScaffold(
      controller: controller,
      floatingActionButton: FloatingActionButton(
        key: const Key('create_group_fab'),
        tooltip: 'Create group trip',
        onPressed: _openCreateGroup,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 32),
      ),
      child: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 92),
            children: [
              Text(
                'Group Trip',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Choose any location to browse groups within 10 km. Creating or joining still verifies your precise location.',
                style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
              ),
              const SizedBox(height: 14),
              _areaSelector(),
              const SizedBox(height: 14),
              if (controller.isLoading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: WauLoadingIndicator(size: 58)),
                )
              else if (controller.groups.isEmpty)
                const _EmptyGroups()
              else
                ...controller.groups.map(
                  (group) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DestinationGroupCard(
                      group: group,
                      photoUrl: _photoFutures.putIfAbsent(
                        group.id,
                        () => _placeSearch.photoForDestination(
                          group.destination,
                          knownPhotoName: group.destinationPhotoName,
                        ),
                      ),
                      onOpen: () => _openGroup(group),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _areaSelector() {
    return InkWell(
      key: const Key('area_dropdown'),
      borderRadius: BorderRadius.circular(15),
      onTap: _openAreaPicker,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8FF),
          border: Border.all(color: const Color(0xFFC6D8F8)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.location_on_rounded,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                controller.selectedArea,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const Text(
              'Browse',
              style: TextStyle(fontSize: 11, color: AppColors.primary),
            ),
            const SizedBox(width: 3),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAreaPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8FBFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) => Theme(
        data: AppTheme.light,
        child: _AreaPickerSheet(
          placeSearch: _placeSearch,
          controller: controller,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openCreateGroup() async {
    final ownedGroup = controller.ownedOngoingGroup;
    if (ownedGroup != null) {
      await controller.openGroup(ownedGroup.id);
      if (!mounted) return;
      showTravelGroupMessage(
        context,
        'You can create another group after ending ${ownedGroup.name}.',
      );
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => GroupLobbyScreen(controller: controller),
        ),
      );
      return;
    }
    if (!controller.currentUser.isVerified) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => VerificationRequiredScreen(controller: controller),
        ),
      );
      return;
    }
    final created = await showModalBottomSheet<TravelGroup>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF8FBFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (_) => Theme(
        data: AppTheme.light,
        child: CreateGroupSheet(
          controller: controller,
          placeSearchService: _placeSearch,
        ),
      ),
    );
    if (!mounted || created == null) return;
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupLobbyScreen(
          controller: controller,
          initialMessage: 'Group successfully created',
        ),
      ),
    );
    if (deleted == true && mounted) {
      await controller.loadGroups();
      if (mounted) showTravelGroupMessage(context, 'Group deleted');
    }
  }

  Future<void> _openGroup(TravelGroup group) async {
    await controller.openGroup(group.id);
    if (!mounted) return;
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupDetailsScreen(controller: controller),
      ),
    );
    if (mounted) {
      await controller.loadGroups();
      if (deleted == true && mounted) {
        showTravelGroupMessage(context, 'Group deleted');
      }
    }
  }
}

class _DestinationGroupCard extends StatelessWidget {
  const _DestinationGroupCard({
    required this.group,
    required this.photoUrl,
    required this.onOpen,
  });

  final TravelGroup group;
  final Future<String?> photoUrl;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isOpen = group.joinMode == JoinMode.open && !group.isFull;
    return Semantics(
      button: true,
      label:
          '${group.destination}, ${group.name}, created by ${group.creatorName}',
      child: Material(
        color: const Color(0xFF174982),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: SizedBox(
            height: 190,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _GroupPhoto(photoUrl: photoUrl),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: [0, .48, 1],
                      colors: [
                        Color(0xED082A55),
                        Color(0xB8174A7F),
                        Color(0x1A0A2445),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.destination,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                          shadows: [
                            Shadow(blurRadius: 5, color: Colors.black45),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      SizedBox(
                        width: 225,
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      _DetailLine(
                        icon: Icons.person_outline_rounded,
                        text: 'Created by ${group.creatorName}',
                      ),
                      const SizedBox(height: 4),
                      _DetailLine(
                        icon: Icons.groups_rounded,
                        text:
                            '${group.memberCount} / ${group.maxMembers} travellers',
                      ),
                      const SizedBox(height: 4),
                      _DetailLine(
                        icon: Icons.circle,
                        iconColor: isOpen
                            ? const Color(0xFF42D477)
                            : const Color(0xFFFFB24A),
                        text: isOpen ? 'Open' : 'Closed',
                      ),
                      const Spacer(),
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1673F9),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View group',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupPhoto extends StatelessWidget {
  const _GroupPhoto({required this.photoUrl});

  final Future<String?> photoUrl;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: photoUrl,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) return const _PhotoFallback();
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const _PhotoFallback(),
        );
      },
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFF174982), Color(0xFF8EB7E8)]),
    ),
    child: Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Icon(Icons.landscape_rounded, size: 72, color: Colors.white38),
      ),
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text, this.iconColor});

  final IconData icon;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: icon == Icons.circle ? 11 : 16,
        color: iconColor ?? Colors.white,
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    ],
  );
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Column(
      children: [
        Icon(Icons.groups_outlined, size: 42, color: AppColors.primary),
        SizedBox(height: 10),
        Text('No group trips in this area yet.'),
        SizedBox(height: 4),
        Text(
          'Tap + to start one.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
      ],
    ),
  );
}

class _AreaPickerSheet extends StatefulWidget {
  const _AreaPickerSheet({required this.placeSearch, required this.controller});

  final TravelPlaceSearchService placeSearch;
  final TravelGroupController controller;

  @override
  State<_AreaPickerSheet> createState() => _AreaPickerSheetState();
}

class _AreaPickerSheetState extends State<_AreaPickerSheet> {
  static const quickLocations = [
    'Setia City Mall',
    'KLCC',
    'Sunway Pyramid',
    'Batu Caves',
    'Bukit Bintang, Kuala Lumpur',
    'i-City',
  ];

  final _query = TextEditingController();
  List<TravelGroupPlace> _results = const [];
  bool _searching = false;
  bool _resolving = false;
  bool _hasSearched = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _hasSearched = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _hasSearched = false;
      _error = null;
    });
    try {
      final results = await widget.placeSearch.search(query, placesOnly: false);
      if (!mounted || _query.text.trim() != query) return;
      setState(() {
        _results = results;
        _hasSearched = true;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not search locations. Check the backend service.',
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _usePreciseLocation() async {
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const TravelGroupException(
          'Turn on Location Services to use your current area.',
          'location_disabled',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const TravelGroupException(
          'Allow precise location access to find your current area.',
          'location_permission_required',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final area = await widget.placeSearch.areaForCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      await widget.controller.setArea(
        area,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (mounted) Navigator.pop(context);
    } on TravelGroupException catch (error) {
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = 'Could not determine your current area. Try again.';
        });
      }
    }
  }

  Future<void> _selectArea(TravelGroupPlace location) async {
    setState(() => _resolving = true);
    try {
      await widget.controller.setArea(
        location.name,
        latitude: location.latitude,
        longitude: location.longitude,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = 'Could not select this location. Try again.';
        });
      }
    }
  }

  Future<void> _selectQuickLocation(String name) async {
    setState(() => _resolving = true);
    try {
      final matches = await widget.placeSearch.search(name, placesOnly: false);
      if (!mounted) return;
      if (matches.isEmpty) {
        setState(() {
          _resolving = false;
          _error = 'No locations found for $name.';
        });
        return;
      }
      await _selectArea(matches.first);
    } catch (_) {
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = 'Could not load $name. Check the backend service.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        4,
        18,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose your area',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose any place as the centre of the 10 km discovery area. Joining and creating still use your precise location.',
              style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('use_precise_area_button'),
                onPressed: _resolving ? null : _usePreciseLocation,
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Use my precise location'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('area_search_field'),
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Search any location',
                hintText: 'e.g. Setia City Mall, KLCC, Shah Alam',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: WauLoadingIndicator(size: 22),
                        ),
                      )
                    : null,
              ),
              onChanged: _search,
              onSubmitted: _search,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 11, color: Colors.red),
                ),
              ),
            if (_hasSearched &&
                !_searching &&
                _results.isEmpty &&
                _error == null)
              Container(
                key: const Key('area_empty_state'),
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceBlue,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.location_off_outlined, color: AppColors.primary),
                    SizedBox(height: 5),
                    Text('No locations found'),
                    Text(
                      'Try a place, landmark, neighbourhood, or city.',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Search results',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AppColors.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < _results.length; index++) ...[
                      ListTile(
                        key: Key('area_result_$index'),
                        dense: true,
                        leading: const Icon(
                          Icons.location_on_outlined,
                          color: AppColors.primary,
                        ),
                        title: Text(_results[index].name),
                        subtitle: Text(
                          _results[index].address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _resolving
                            ? null
                            : () => _selectArea(_results[index]),
                      ),
                      if (index < _results.length - 1)
                        const Divider(height: 1, indent: 52),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'Popular locations',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: quickLocations
                  .map(
                    (location) => ActionChip(
                      label: Text(location),
                      backgroundColor: const Color(0xF2FFFFFF),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      labelStyle: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w600,
                      ),
                      onPressed: _resolving
                          ? null
                          : () => _selectQuickLocation(location),
                    ),
                  )
                  .toList(),
            ),
            if (_resolving)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(child: WauLoadingIndicator(size: 58)),
              ),
          ],
        ),
      ),
    );
  }
}
