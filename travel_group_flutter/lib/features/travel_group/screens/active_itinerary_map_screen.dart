import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/travel_group_controller.dart';
import '../models/travel_group_models.dart';
import '../services/live_trip_location_service.dart';
import '../services/travel_map_service.dart';
import '../widgets/travel_group_widgets.dart';

class ActiveItineraryMapScreen extends StatefulWidget {
  const ActiveItineraryMapScreen({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  State<ActiveItineraryMapScreen> createState() =>
      _ActiveItineraryMapScreenState();
}

class _ActiveItineraryMapScreenState extends State<ActiveItineraryMapScreen> {
  static const _memberColors = <Color>[
    Color(0xFF3266CC),
    Color(0xFFF2A64A),
    Color(0xFF5BAF8B),
    Color(0xFF8A68C7),
    Color(0xFFE05D68),
  ];
  static const _markerHues = <double>[
    BitmapDescriptor.hueAzure,
    BitmapDescriptor.hueOrange,
    BitmapDescriptor.hueGreen,
    BitmapDescriptor.hueViolet,
    BitmapDescriptor.hueRose,
  ];

  final TravelMapService _mapService = MockTravelMapService();
  late final LiveTripLocationService _liveLocationService;
  StreamSubscription<List<LiveMemberLocation>>? _memberSubscription;
  StreamSubscription<Position>? _positionSubscription;
  GoogleMapController? _googleMapController;
  Timer? _timer;
  List<LiveMemberLocation> _members = const [];
  double _progress = 0;
  bool _paused = false;
  bool _locationUnavailable = false;

  TravelGroupController get controller => widget.controller;

  ItineraryStop? get currentStop {
    for (final stop in controller.itinerary) {
      if (stop.status == StopStatus.current) return stop;
    }
    return null;
  }

  List<LatLng> get _route => demoGroupRoute
      .map((point) => LatLng(point.latitude, point.longitude))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _liveLocationService = controller.createLiveTripLocationService();
    _memberSubscription =
        _liveLocationService.watchLocations().listen((members) {
      if (mounted) setState(() => _members = members);
    });
    unawaited(_startLocationSharing());
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!_paused && mounted) {
        setState(
            () => _progress = (_progress + .018).clamp(0.0, .98).toDouble());
      }
    });
  }

  Future<void> _startLocationSharing() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _locationUnavailable = true);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationUnavailable = true);
        return;
      }
      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      );
      _positionSubscription =
          Geolocator.getPositionStream(locationSettings: settings)
              .listen((position) {
        _liveLocationService.publishOwnLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
        );
      });
    } catch (_) {
      if (mounted) setState(() => _locationUnavailable = true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    final memberSubscription = _memberSubscription;
    if (memberSubscription != null) unawaited(memberSubscription.cancel());
    final positionSubscription = _positionSubscription;
    if (positionSubscription != null) unawaited(positionSubscription.cancel());
    unawaited(_liveLocationService.dispose());
    _googleMapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _mapService.snapshot(_progress);
    final stop = currentStop;
    final currentIndex = stop == null
        ? controller.itinerary.length
        : controller.itinerary.indexOf(stop);
    final isFinalStop =
        stop != null && currentIndex == controller.itinerary.length - 1;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F2),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              top: 88,
              child: _buildMap(currentIndex),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _NavigationHeader(
                instruction:
                    isFinalStop ? 'Continue for 300 m' : snapshot.instruction,
                stopName: stop?.placeName ?? 'Route complete',
                current: currentIndex + 1,
                total: controller.itinerary.length,
                isFinalStop: isFinalStop,
              ),
            ),
            Positioned(
              left: 20,
              top: 102,
              child: _GroupPresenceBubble(
                members: _members,
                fallbackCount: controller.activeGroup!.memberIds.length,
                onTap: _showMemberLocations,
              ),
            ),
            if (_locationUnavailable)
              Positioned(
                left: 20,
                right: 20,
                top: 148,
                child: _LocationNotice(onTap: _startLocationSharing),
              ),
            Positioned(
              right: 24,
              top: 176,
              child: _MapBubble(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${isFinalStop ? 'FINAL' : 'NEXT'} STOP · ${snapshot.etaMinutes} MIN',
                      style: const TextStyle(
                          fontSize: 9, color: AppColors.primary),
                    ),
                    SizedBox(
                      width: 130,
                      child: Text(
                        stop?.placeName ?? 'Route complete',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 20,
              bottom: 228,
              child: _ConditionButton(
                icon: Icons.wb_sunny_outlined,
                value: '29°',
                color: Color(0xFFFFA60D),
              ),
            ),
            const Positioned(
              left: 20,
              bottom: 168,
              child: _ConditionButton(
                icon: Icons.traffic_rounded,
                value: 'Medium',
                color: Color(0xFFE5332E),
              ),
            ),
            Positioned(
              right: 20,
              bottom: 168,
              child: _GroupChatButton(
                unreadCount: 2,
                onPressed: () => showTravelGroupMessage(context,
                    'Group chat integration is ready for your team module.'),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _RouteFooter(
                controller: controller,
                stop: stop,
                snapshot: snapshot,
                index: currentIndex,
                isFinalStop: isFinalStop,
                onComplete: stop == null || !controller.isCreator
                    ? null
                    : () => _complete(stop),
                onItinerary: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(int currentIndex) {
    final memberMarkers = _members.indexed.map((entry) {
      final index = entry.$1;
      final member = entry.$2;
      return Marker(
        markerId: MarkerId('member_${member.userId}'),
        position:
            LatLng(member.coordinate.latitude, member.coordinate.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(
            _markerHues[index % _markerHues.length]),
        infoWindow: InfoWindow(
          title: member.isCurrentUser
              ? '${member.displayName} (you)'
              : member.displayName,
          snippet: member.isFresh ? 'Live now' : 'Location may be stale',
        ),
      );
    });
    final stopMarkers = controller.itinerary.indexed.map((entry) {
      final index = entry.$1;
      final stop = entry.$2;
      final routeIndex = controller.itinerary.length <= 1
          ? _route.length - 1
          : ((index / (controller.itinerary.length - 1)) * (_route.length - 1))
              .round();
      final hue = stop.status == StopStatus.completed
          ? BitmapDescriptor.hueGreen
          : stop.status == StopStatus.current
              ? BitmapDescriptor.hueAzure
              : BitmapDescriptor.hueViolet;
      return Marker(
        markerId: MarkerId('stop_${stop.id}'),
        position: _route[routeIndex.clamp(0, _route.length - 1).toInt()],
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: 'Stop ${index + 1}: ${stop.placeName}',
          snippet: stop.status == StopStatus.completed
              ? 'Completed'
              : index == currentIndex
                  ? 'Next stop'
                  : 'Upcoming',
        ),
      );
    });
    return GoogleMap(
      initialCameraPosition:
          CameraPosition(target: _route[_route.length ~/ 2], zoom: 15.8),
      onMapCreated: (mapController) {
        _googleMapController = mapController;
        unawaited(_fitRoute());
      },
      markers: {...memberMarkers, ...stopMarkers},
      polylines: {
        Polyline(
          polylineId: const PolylineId('group_route_shadow'),
          points: _route,
          color: const Color(0xFF91B7FF),
          width: 11,
        ),
        Polyline(
          polylineId: const PolylineId('group_route'),
          points: _route,
          color: AppColors.primary,
          width: 6,
        ),
      },
      circles: _members
          .where((member) => member.isCurrentUser)
          .map(
            (member) => Circle(
              circleId: const CircleId('current_user_accuracy'),
              center: LatLng(
                  member.coordinate.latitude, member.coordinate.longitude),
              radius: (member.accuracyMeters ?? 12).clamp(8, 80).toDouble(),
              fillColor: const Color(0x263266CC),
              strokeColor: const Color(0x553266CC),
              strokeWidth: 1,
            ),
          )
          .toSet(),
      padding: const EdgeInsets.only(bottom: 170),
      compassEnabled: false,
      mapToolbarEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      onTap: (_) => setState(() => _paused = false),
    );
  }

  Future<void> _fitRoute() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final mapController = _googleMapController;
    if (mapController == null || !mounted) return;
    var minLat = _route.first.latitude;
    var maxLat = _route.first.latitude;
    var minLng = _route.first.longitude;
    var maxLng = _route.first.longitude;
    for (final point in _route.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    try {
      await mapController.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
              southwest: LatLng(minLat, minLng),
              northeast: LatLng(maxLat, maxLng)),
          58,
        ),
      );
    } catch (_) {
      // The map can briefly reject bounds while its Android surface attaches.
    }
  }

  Future<void> _showMemberLocations() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _MemberLocationsSheet(
        members: _members,
        currentUserId: controller.currentUser.id,
        colors: _memberColors,
      ),
    );
  }

  Future<void> _complete(ItineraryStop stop) async {
    try {
      await controller.completeStop(stop);
      if (!mounted) return;
      if (controller.activeGroup!.status == GroupStatus.completed) {
        showTravelGroupMessage(context, 'Every itinerary stop is complete.');
        Navigator.pop(context);
      } else {
        setState(() => _progress = 0);
        showTravelGroupMessage(context,
            'Stop completed. The shared route advanced for every member.');
      }
    } on TravelGroupException catch (error) {
      if (mounted) showTravelGroupMessage(context, error.message, error: true);
    }
  }
}

class _NavigationHeader extends StatelessWidget {
  const _NavigationHeader({
    required this.instruction,
    required this.stopName,
    required this.current,
    required this.total,
    required this.isFinalStop,
  });

  final String instruction;
  final String stopName;
  final int current;
  final int total;
  final bool isFinalStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: const Color(0xFF2E60C4),
      child: Row(
        children: [
          const Icon(Icons.turn_right_rounded, size: 48, color: Colors.white),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(instruction,
                    style: const TextStyle(fontSize: 22, color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  'towards $stopName · ${isFinalStop ? 'Final stop' : 'Stop'} $current of $total',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFFE0EDFF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteFooter extends StatelessWidget {
  const _RouteFooter({
    required this.controller,
    required this.stop,
    required this.snapshot,
    required this.index,
    required this.isFinalStop,
    required this.onComplete,
    required this.onItinerary,
  });

  final TravelGroupController controller;
  final ItineraryStop? stop;
  final NavigationSnapshot snapshot;
  final int index;
  final bool isFinalStop;
  final VoidCallback? onComplete;
  final VoidCallback onItinerary;

  @override
  Widget build(BuildContext context) {
    final total = controller.itinerary.length;
    final completed = controller.itinerary
        .where((item) => item.status == StopStatus.completed)
        .length;
    final eta = DateTime.now().add(Duration(minutes: snapshot.etaMinutes));
    final hour = eta.hour % 12 == 0 ? 12 : eta.hour % 12;
    final etaLabel =
        '$hour:${eta.minute.toString().padLeft(2, '0')} ${eta.hour >= 12 ? 'PM' : 'AM'}';
    return Container(
      height: 160,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Text(
            '⌃  Group trip in progress · ${isFinalStop ? 'Final stop' : 'Stop'} ${index + 1} of $total',
            style:
                const TextStyle(fontSize: 10, color: AppColors.secondaryText),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('NEXT STOP',
                        style:
                            TextStyle(fontSize: 9, color: AppColors.primary)),
                    Text(
                      stop?.placeName ?? 'Route complete',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${snapshot.etaMinutes} min',
                  style: const TextStyle(fontSize: 21)),
              const SizedBox(width: 10),
              Text(
                '${snapshot.distanceKm} km · ETA $etaLabel',
                style: const TextStyle(
                    fontSize: 10, color: AppColors.secondaryText),
              ),
            ],
          ),
          const SizedBox(height: 5),
          LinearProgressIndicator(
            value: total == 0 ? 0.0 : completed / total,
            minHeight: 4,
            backgroundColor: const Color(0xFFDBE5F5),
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 50,
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Color(0xFFBF2424)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onComplete,
                    icon: Icon(
                        onComplete == null
                            ? Icons.sync_rounded
                            : Icons.check_circle_outline,
                        size: 18),
                    label: Text(
                      onComplete == null
                          ? 'Following creator progress'
                          : isFinalStop
                              ? 'Finish at final stop'
                              : 'Mark stop completed',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 56,
                  child: IconButton.filledTonal(
                    onPressed: onItinerary,
                    icon: const Icon(Icons.format_list_bulleted,
                        color: AppColors.primary),
                    tooltip: 'Itinerary',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupPresenceBubble extends StatelessWidget {
  const _GroupPresenceBubble({
    required this.members,
    required this.fallbackCount,
    required this.onTap,
  });

  final List<LiveMemberLocation> members;
  final int fallbackCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = members.isEmpty ? fallbackCount : members.length;
    const colors = [Color(0xFF3266CC), Color(0xFFF2A64A), Color(0xFF5BAF8B)];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 4,
      shadowColor: const Color(0x26141F33),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 36,
          padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 52,
                child: Stack(
                  children: List.generate(
                    3,
                    (index) => Positioned(
                      left: index * 14,
                      top: 6,
                      child: _MiniAvatar(
                        label: members.length > index
                            ? _initials(members[index].displayName)
                            : '',
                        color: colors[index],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text('$count together', style: const TextStyle(fontSize: 10)),
              const SizedBox(width: 5),
              const Icon(Icons.keyboard_arrow_up_rounded,
                  size: 16, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberLocationsSheet extends StatelessWidget {
  const _MemberLocationsSheet({
    required this.members,
    required this.currentUserId,
    required this.colors,
  });

  final List<LiveMemberLocation> members;
  final String currentUserId;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    LiveMemberLocation? current;
    for (final member in members) {
      if (member.userId == currentUserId) {
        current = member;
        break;
      }
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Live group locations',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
                'Only members in this active trip can see these locations.'),
            const SizedBox(height: 12),
            for (final entry in members.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: colors[entry.$1 % colors.length],
                  child: Text(_initials(entry.$2.displayName),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 11)),
                ),
                title: Text(entry.$2.isCurrentUser
                    ? '${entry.$2.displayName} (you)'
                    : entry.$2.displayName),
                subtitle: Text(_memberStatus(entry.$2, current)),
                trailing: Icon(
                  Icons.circle,
                  size: 10,
                  color:
                      entry.$2.isFresh ? AppColors.success : AppColors.warning,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _memberStatus(LiveMemberLocation member, LiveMemberLocation? current) {
    final seconds = DateTime.now().difference(member.updatedAt).inSeconds;
    final freshness = seconds < 5 ? 'Live now' : 'Updated ${seconds}s ago';
    if (current == null || current.userId == member.userId) return freshness;
    final meters = Geolocator.distanceBetween(
      current.coordinate.latitude,
      current.coordinate.longitude,
      member.coordinate.latitude,
      member.coordinate.longitude,
    );
    final distance = meters < 1000
        ? '${meters.round()} m away'
        : '${(meters / 1000).toStringAsFixed(1)} km away';
    return '$freshness · $distance';
  }
}

class _LocationNotice extends StatelessWidget {
  const _LocationNotice({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF6E8),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(Icons.location_off_outlined,
                  size: 17, color: AppColors.warning),
              SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Location is off. Showing your prototype position.',
                      style: TextStyle(fontSize: 10))),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapBubble extends StatelessWidget {
  const _MapBubble({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1F141F33), blurRadius: 8, offset: Offset(0, 3))
        ],
      ),
      child: child,
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child:
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 7)),
    );
  }
}

class _ConditionButton extends StatelessWidget {
  const _ConditionButton(
      {required this.icon, required this.value, required this.color});

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 7, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          Text(value, style: TextStyle(fontSize: value.length > 3 ? 9 : 14)),
        ],
      ),
    );
  }
}

class _GroupChatButton extends StatelessWidget {
  const _GroupChatButton({required this.unreadCount, required this.onPressed});

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          elevation: 4,
          shadowColor: const Color(0x26141F33),
          child: IconButton(
            onPressed: onPressed,
            icon: const Icon(Icons.chat_bubble_outline_rounded,
                color: AppColors.primary),
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            right: -3,
            top: -5,
            child: CircleAvatar(
              radius: 9,
              backgroundColor: const Color(0xFFE5332E),
              child: Text('$unreadCount',
                  style: const TextStyle(color: Colors.white, fontSize: 9)),
            ),
          ),
      ],
    );
  }
}

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  return parts.map((part) => part[0].toUpperCase()).take(2).join();
}
