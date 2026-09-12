import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../preference_recommender/features/routes/navigation_sensor.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/live_trip_location_service.dart';
import '../services/member_location_clusters.dart';
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
  List<LiveMemberLocation> _members = const [];
  LatLng? _candidate;
  GoogleMapController? _mapController;
  MethodChannel? _poiChannel;
  bool _saving = false;
  final Map<int, BitmapDescriptor> _stackIcons = {};
  bool _buildingStackIcons = false;

  Future<void> _prepareStackIcons() async {
    if (_buildingStackIcons) return;
    _buildingStackIcons = true;
    try {
      for (var count = 2; count <= _members.length; count++) {
        if (_stackIcons.containsKey(count)) continue;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawCircle(
          const Offset(34, 24),
          21,
          Paint()..color = const Color(0xffa8c4ff),
        );
        canvas.drawCircle(
          const Offset(26, 32),
          23,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          const Offset(26, 32),
          20,
          Paint()..color = const Color(0xff3266cc),
        );
        final text = TextPainter(
          text: TextSpan(
            text: '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(26 - text.width / 2, 32 - text.height / 2));
        final picture = recorder.endRecording();
        final image = await picture.toImage(60, 60);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        _stackIcons[count] = BitmapDescriptor.bytes(
          bytes!.buffer.asUint8List(),
          width: 40,
          height: 40,
        );
      }
      if (mounted) setState(() {});
    } finally {
      _buildingStackIcons = false;
    }
  }

  void _openStack(List<LiveMemberLocation> members) {
    if (members.length == 1) {
      _openMemberProfile(members.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('${members.length} travellers here')),
            for (final member in members)
              ListTile(
                title: Text(member.displayName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openMemberProfile(member);
                },
              ),
          ],
        ),
      ),
    );
  }

  bool _hasFocusedLiveLocations = false;
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
        unawaited(_prepareStackIcons());
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
    final coordinate = widget.controller.effectiveLocation(
      position.latitude,
      position.longitude,
    );
    try {
      await _locationService.publishOwnLocation(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
        accuracyMeters: position.accuracy,
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
      appBar: AppBar(
        title: Text(
          widget.controller.isCreator
              ? 'Set meetup point'
              : 'Live group locations',
        ),
      ),
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
              onTap: widget.controller.isCreator
                  ? (value) => setState(() {
                      _candidate = value;
                      _label.text = 'Dropped pin';
                    })
                  : null,
              markers: {
                for (final cluster in clusterMemberLocations(_members))
                  Marker(
                    markerId: MarkerId('member_${cluster.first.userId}'),
                    position: LatLng(
                      cluster.first.coordinate.latitude,
                      cluster.first.coordinate.longitude,
                    ),
                    infoWindow: InfoWindow(
                      title: cluster.map((m) => m.displayName).join(', '),
                    ),
                    onTap: () => _openStack(cluster),
                    icon:
                        _stackIcons[cluster.length] ??
                        BitmapDescriptor.defaultMarkerWithHue(
                          _markerHue(
                            cluster.first,
                            _members.indexOf(cluster.first),
                          ),
                        ),
                  ),
                if (candidate != null)
                  Marker(
                    markerId: const MarkerId('meetup_candidate'),
                    position: candidate,
                    draggable: widget.controller.isCreator,
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
                    readOnly: !widget.controller.isCreator,
                    decoration: const InputDecoration(
                      labelText: 'Meetup point name',
                      hintText: 'e.g. Main entrance',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          widget.controller.isCreator && inRange && !_saving
                          ? _save
                          : null,
                      child: Text(
                        !widget.controller.isCreator
                            ? 'Only the creator can change meetup'
                            : _saving
                            ? 'Saving...'
                            : 'Save meetup point',
                      ),
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
      if (call.method != 'onPoiTap' ||
          !mounted ||
          !widget.controller.isCreator) {
        return;
      }
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
