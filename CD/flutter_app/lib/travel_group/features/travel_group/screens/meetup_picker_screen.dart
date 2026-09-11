import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../preference_recommender/features/routes/navigation_sensor.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/live_trip_location_service.dart';
import '../widgets/travel_group_widgets.dart';
import 'group_member_profile_screen.dart';

class MeetupPickerScreen extends StatefulWidget {
  const MeetupPickerScreen({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  State<MeetupPickerScreen> createState() => _MeetupPickerScreenState();
}

class _MeetupPickerScreenState extends State<MeetupPickerScreen> {
  static const maximumMemberDistanceMeters = 5000.0;
  final _label = TextEditingController(text: 'Group meetup point');
  late final LiveTripLocationService _locationService;
  StreamSubscription<List<LiveMemberLocation>>? _memberSubscription;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _demoMemberTimer;
  List<LiveMemberLocation> _members = const [];
  LatLng? _candidate;
  GoogleMapController? _mapController;
  MethodChannel? _poiChannel;
  bool _saving = false;
  bool _hasFocusedLiveLocations = false;
  bool _simulatingDemoMembers = false;
  bool _simulationCallInFlight = false;
  Position? _lastPosition;
  String? _locationError;

  TravelGroup get group => widget.controller.activeGroup!;

  @override
  void initState() {
    super.initState();
    if (group.meetupLatitude != null && group.meetupLongitude != null) {
      _candidate = LatLng(group.meetupLatitude!, group.meetupLongitude!);
      if (group.meetupPoint.trim().isNotEmpty) {
        _label.text = group.meetupPoint;
      }
    }
    _locationService = widget.controller.createLiveTripLocationService();
    _memberSubscription = _locationService.watchLocations().listen(
      (members) {
        if (!mounted) return;
        setState(() {
          _members = members;
          _candidate ??= _centroid(members);
        });
        if (_simulatingDemoMembers && _everyoneAtMeetup()) {
          _stopDemoMemberSimulation(arrived: true);
        }
        if (!_hasFocusedLiveLocations && members.isNotEmpty) {
          _hasFocusedLiveLocations = true;
          unawaited(_focusLiveLocations());
        }
      },
      onError: (Object error) {
        if (mounted) setState(() => _locationError = error.toString());
      },
    );
    unawaited(_startOwnLocation());
  }

  Future<void> _startOwnLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: navigationLocationSettings,
    ).listen(_publishPosition);
    try {
      await _publishPosition(
        await Geolocator.getCurrentPosition(
          locationSettings: navigationLocationSettings,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _locationError = error.toString());
    }
  }

  Future<void> _publishPosition(Position position) async {
    _lastPosition = position;
    final coordinate = widget.controller.effectiveLocation(
      position.latitude,
      position.longitude,
    );
    try {
      await _locationService.publishOwnLocation(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
        accuracyMeters: widget.controller.isUsingSimulatedLocation
            ? 5
            : position.accuracy,
      );
      if (mounted && _locationError != null) {
        setState(() => _locationError = null);
      }
    } catch (error) {
      if (mounted) setState(() => _locationError = error.toString());
    }
  }

  @override
  void dispose() {
    _poiChannel?.setMethodCallHandler(null);
    _mapController?.dispose();
    _label.dispose();
    _memberSubscription?.cancel();
    _positionSubscription?.cancel();
    _demoMemberTimer?.cancel();
    unawaited(_locationService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidate = _candidate;
    final farthest = candidate == null ? null : _farthestDistance(candidate);
    final hasEnoughMembers = _members.isNotEmpty;
    final inRange =
        hasEnoughMembers &&
        farthest != null &&
        farthest <= maximumMemberDistanceMeters;
    return Scaffold(
      appBar: AppBar(title: const Text('Set meetup point')),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(
                  group.destinationLatitude ?? 3.1579,
                  group.destinationLongitude ?? 101.7123,
                ),
                zoom: 12.5,
              ),
              onMapCreated: _onMapCreated,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              compassEnabled: true,
              trafficEnabled: true,
              zoomControlsEnabled: false,
              buildingsEnabled: false,
              indoorViewEnabled: false,
              tiltGesturesEnabled: false,
              mapToolbarEnabled: false,
              onTap: (value) => setState(() {
                _candidate = value;
                _label.text = 'Dropped pin';
              }),
              markers: {
                for (var index = 0; index < _members.length; index++)
                  Marker(
                    markerId: MarkerId('member_${_members[index].userId}'),
                    position: LatLng(
                      _members[index].coordinate.latitude,
                      _members[index].coordinate.longitude,
                    ),
                    infoWindow: InfoWindow(title: _members[index].displayName),
                    onTap: () => _openMemberProfile(_members[index]),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      _markerHue(_members[index], index),
                    ),
                  ),
                if (candidate != null)
                  Marker(
                    markerId: const MarkerId('meetup_candidate'),
                    position: candidate,
                    draggable: true,
                    onDragEnd: (value) => setState(() => _candidate = value),
                    infoWindow: const InfoWindow(title: 'Proposed meetup'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen,
                    ),
                  ),
              },
              circles: candidate == null
                  ? const {}
                  : {
                      Circle(
                        circleId: const CircleId('meetup_range'),
                        center: candidate,
                        radius: maximumMemberDistanceMeters,
                        fillColor: const Color(0x183266CC),
                        strokeColor: const Color(0x883266CC),
                        strokeWidth: 2,
                      ),
                    },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_members.length} live ${_members.length == 1 ? 'location' : 'locations'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (_locationError != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      'Location sharing failed: $_locationError',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFB3261E),
                      ),
                    ),
                  ],
                  if (kDebugMode) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        TextButton.icon(
                          key: const Key('meetup_test_location_button'),
                          onPressed: _toggleTestLocation,
                          icon: const Icon(Icons.science_outlined, size: 17),
                          label: Text(
                            widget.controller.isUsingSimulatedLocation
                                ? 'Use actual GPS'
                                : 'Test at destination',
                          ),
                        ),
                        if (widget.controller.isCreator)
                          TextButton.icon(
                            key: const Key('simulate_demo_members_button'),
                            onPressed: candidate == null
                                ? null
                                : _toggleDemoMemberSimulation,
                            icon: Icon(
                              _simulatingDemoMembers
                                  ? Icons.stop_circle_outlined
                                  : Icons.directions_walk_rounded,
                              size: 17,
                            ),
                            label: Text(
                              _simulatingDemoMembers
                                  ? 'Stop demo travellers'
                                  : 'Simulate travellers',
                            ),
                          ),
                      ],
                    ),
                    if (_simulatingDemoMembers)
                      const Padding(
                        padding: EdgeInsets.only(left: 12, bottom: 3),
                        child: Text(
                          'Each demo traveller moves closer every 2 seconds.',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    !hasEnoughMembers
                        ? 'Waiting for your precise location.'
                        : _members.length == 1
                        ? 'Using your location for now. Recheck after travellers join.'
                        : inRange
                        ? 'This point is within 5 km of every traveller.'
                        : 'Move the green pin closer to everyone. It must be within 5 km of each traveller.',
                    style: TextStyle(
                      fontSize: 12,
                      color: inRange
                          ? AppColors.success
                          : AppColors.secondaryText,
                    ),
                  ),
                  if (_members.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _members.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 7),
                        itemBuilder: (context, index) {
                          final location = _members[index];
                          return ActionChip(
                            avatar: Icon(
                              location.isFresh
                                  ? Icons.location_on_rounded
                                  : Icons.location_off_rounded,
                              size: 16,
                              color: location.isFresh
                                  ? AppColors.success
                                  : AppColors.secondaryText,
                            ),
                            label: Text(
                              location.isCurrentUser
                                  ? '${location.displayName} (you)'
                                  : location.displayName,
                            ),
                            onPressed: () => _openMemberProfile(location),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: _label,
                    decoration: const InputDecoration(
                      labelText: 'Meetup point name',
                      hintText: 'e.g. Main entrance',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: inRange && !_saving && !_simulatingDemoMembers
                          ? _save
                          : null,
                      child: Text(_saving ? 'Saving...' : 'Save meetup point'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleTestLocation() {
    if (widget.controller.isUsingSimulatedLocation) {
      widget.controller.useActualLocation();
    } else {
      widget.controller.simulateLocationNearDestination();
    }
    final position = _lastPosition;
    if (position != null) unawaited(_publishPosition(position));
    setState(() {});
  }

  Future<void> _toggleDemoMemberSimulation() async {
    if (_simulatingDemoMembers) {
      _stopDemoMemberSimulation();
      return;
    }
    final candidate = _candidate;
    if (candidate == null) return;
    setState(() {
      _simulatingDemoMembers = true;
      _locationError = null;
    });

    // Put the creator at the proposed point as part of this explicit test mode.
    widget.controller.simulateLocationAt(
      candidate.latitude,
      candidate.longitude,
    );
    try {
      await _locationService.publishOwnLocation(
        latitude: candidate.latitude,
        longitude: candidate.longitude,
        accuracyMeters: 5,
      );
      final count = await _runDemoMemberTick(resetPositions: true);
      if (!mounted || !_simulatingDemoMembers) return;
      if (count == 0) {
        setState(() {
          _locationError = 'No travellers labelled (Demo) are in this group.';
        });
        _stopDemoMemberSimulation();
        return;
      }
      _demoMemberTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(_runDemoMemberTick());
      });
    } catch (error) {
      if (mounted) setState(() => _locationError = error.toString());
      _stopDemoMemberSimulation();
    }
  }

  Future<int> _runDemoMemberTick({bool resetPositions = false}) async {
    final candidate = _candidate;
    if (candidate == null || _simulationCallInFlight) return 0;
    _simulationCallInFlight = true;
    try {
      return await widget.controller.simulateDemoMembersTowardMeetup(
        latitude: candidate.latitude,
        longitude: candidate.longitude,
        resetPositions: resetPositions,
      );
    } catch (error) {
      if (mounted) setState(() => _locationError = error.toString());
      _stopDemoMemberSimulation();
      return 0;
    } finally {
      _simulationCallInFlight = false;
    }
  }

  bool _everyoneAtMeetup() {
    final candidate = _candidate;
    if (candidate == null || _members.length < group.memberCount) return false;
    return _members.every(
      (member) =>
          Geolocator.distanceBetween(
            candidate.latitude,
            candidate.longitude,
            member.coordinate.latitude,
            member.coordinate.longitude,
          ) <=
          150,
    );
  }

  void _stopDemoMemberSimulation({bool arrived = false}) {
    _demoMemberTimer?.cancel();
    _demoMemberTimer = null;
    if (!mounted) return;
    setState(() => _simulatingDemoMembers = false);
    if (arrived) {
      showTravelGroupMessage(
        context,
        'All demo travellers have reached the meetup point.',
      );
    }
  }

  double _markerHue(LiveMemberLocation member, int index) {
    if (member.isCurrentUser) return BitmapDescriptor.hueAzure;
    const hues = <double>[
      BitmapDescriptor.hueViolet,
      BitmapDescriptor.hueOrange,
      BitmapDescriptor.hueRose,
    ];
    return hues[index % hues.length];
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _poiChannel = MethodChannel('ohmy/google_map_poi/${controller.mapId}');
    _poiChannel!.setMethodCallHandler((call) async {
      if (call.method != 'onPoiTap' || !mounted) return;
      final poi = Map<String, dynamic>.from(call.arguments as Map);
      final latitude = (poi['latitude'] as num?)?.toDouble();
      final longitude = (poi['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) return;
      setState(() {
        _candidate = LatLng(latitude, longitude);
        _label.text = poi['name']?.toString().trim().isNotEmpty == true
            ? poi['name'].toString()
            : 'Selected place';
      });
    });
    if (_members.isNotEmpty) unawaited(_focusLiveLocations());
  }

  Future<void> _focusLiveLocations() async {
    final map = _mapController;
    if (map == null || _members.isEmpty) return;
    final points = <LatLng>[
      for (final member in _members)
        LatLng(member.coordinate.latitude, member.coordinate.longitude),
    ];
    final candidate = _candidate;
    if (candidate != null) points.add(candidate);
    if (points.length == 1) {
      await map.animateCamera(CameraUpdate.newLatLngZoom(points.single, 16));
      return;
    }
    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;
    for (final point in points.skip(1)) {
      minLatitude = point.latitude < minLatitude ? point.latitude : minLatitude;
      maxLatitude = point.latitude > maxLatitude ? point.latitude : maxLatitude;
      minLongitude = point.longitude < minLongitude
          ? point.longitude
          : minLongitude;
      maxLongitude = point.longitude > maxLongitude
          ? point.longitude
          : maxLongitude;
    }
    if (minLatitude == maxLatitude && minLongitude == maxLongitude) {
      await map.animateCamera(CameraUpdate.newLatLngZoom(points.first, 16));
      return;
    }
    await map.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLatitude, minLongitude),
          northeast: LatLng(maxLatitude, maxLongitude),
        ),
        72,
      ),
    );
  }

  void _openMemberProfile(LiveMemberLocation location) {
    final profiles = widget.controller.members;
    GroupMemberProfile? member;
    for (final profile in profiles) {
      if (profile.userId == location.userId) {
        member = profile;
        break;
      }
    }
    if (member == null) return;
    final selectedMember = member;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GroupMemberProfileScreen(
          member: selectedMember,
          groupName: group.name,
          isCurrentUser: location.isCurrentUser,
        ),
      ),
    );
  }

  LatLng? _centroid(List<LiveMemberLocation> members) {
    if (members.isEmpty) return null;
    final latitude =
        members.fold<double>(
          0,
          (sum, member) => sum + member.coordinate.latitude,
        ) /
        members.length;
    final longitude =
        members.fold<double>(
          0,
          (sum, member) => sum + member.coordinate.longitude,
        ) /
        members.length;
    return LatLng(latitude, longitude);
  }

  double _farthestDistance(LatLng candidate) {
    return _members.fold<double>(0, (farthest, member) {
      final distance = Geolocator.distanceBetween(
        candidate.latitude,
        candidate.longitude,
        member.coordinate.latitude,
        member.coordinate.longitude,
      );
      return distance > farthest ? distance : farthest;
    });
  }

  Future<void> _save() async {
    final candidate = _candidate;
    if (candidate == null) return;
    setState(() => _saving = true);
    try {
      await widget.controller.setMeetupPoint(
        name: _label.text,
        latitude: candidate.latitude,
        longitude: candidate.longitude,
        members: _members,
      );
      if (mounted) Navigator.pop(context, true);
    } on TravelGroupException catch (error) {
      if (mounted) showTravelGroupMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
