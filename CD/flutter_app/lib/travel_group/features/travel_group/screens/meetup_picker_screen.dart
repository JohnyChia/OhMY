import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../preference_recommender/features/routes/navigation_sensor.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/live_trip_location_service.dart';
import '../widgets/travel_group_widgets.dart';

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
  bool _saving = false;

  TravelGroup get group => widget.controller.activeGroup!;

  @override
  void initState() {
    super.initState();
    _locationService = widget.controller.createLiveTripLocationService();
    _memberSubscription = _locationService.watchLocations().listen((members) {
      if (!mounted) return;
      setState(() {
        _members = members;
        _candidate ??= _centroid(members);
      });
    });
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
      _publishPosition(
        await Geolocator.getCurrentPosition(
          locationSettings: navigationLocationSettings,
        ),
      );
    } catch (_) {
      // Other joined members can still be shown if this device has no fix yet.
    }
  }

  void _publishPosition(Position position) {
    _locationService.publishOwnLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
    );
  }

  @override
  void dispose() {
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
    final hasEnoughMembers = _members.length >= 2;
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
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              mapToolbarEnabled: false,
              onTap: (value) => setState(() => _candidate = value),
              markers: {
                for (var index = 0; index < _members.length; index++)
                  Marker(
                    markerId: MarkerId('member_${_members[index].userId}'),
                    position: LatLng(
                      _members[index].coordinate.latitude,
                      _members[index].coordinate.longitude,
                    ),
                    infoWindow: InfoWindow(title: _members[index].displayName),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      index == 0
                          ? BitmapDescriptor.hueAzure
                          : BitmapDescriptor.hueViolet,
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
                  const SizedBox(height: 4),
                  Text(
                    !hasEnoughMembers
                        ? 'Wait for another traveller to join and share their location.'
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
                      onPressed: inRange && !_saving ? _save : null,
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
