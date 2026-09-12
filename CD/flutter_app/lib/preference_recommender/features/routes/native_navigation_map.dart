import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    as navigation;

/// Enables accelerated movement along the active route for emulator testing.
/// It is off unless explicitly supplied with --dart-define.
const bool navigationSimulationEnabled = bool.fromEnvironment(
  'NAVIGATION_SIMULATION',
  defaultValue: false,
);
const double navigationSimulationSpeed = 5;

/// Shared app-shell signal. The regular bottom navigation must not compete
/// with the native turn-by-turn controls while this view is mounted.
final ValueNotifier<bool> navigationExperienceActive = ValueNotifier(false);

class NavigationMemberPin {
  const NavigationMemberPin({
    required this.latitude,
    required this.longitude,
    required this.names,
  });
  final double latitude;
  final double longitude;
  final List<String> names;
}

/// Owns the short-lived Google Navigation SDK session used during a journey.
///
/// The normal discovery map remains a `google_maps_flutter` map. This widget is
/// only mounted by the active navigation page and cleans up the native session
/// when the page is closed or Google reports arrival.
class NativeNavigationMap extends StatefulWidget {
  const NativeNavigationMap({
    super.key,
    required this.destinationName,
    required this.destinationLatitude,
    required this.destinationLongitude,
    required this.routeToken,
    required this.trafficEnabled,
    required this.voiceGuidanceEnabled,
    required this.vibrationEnabled,
    required this.onArrived,
    required this.onLocation,
    required this.onProgress,
    required this.onStatus,
    this.onCameraBearingChanged,
    this.memberPins = const [],
    this.simulationOriginLatitude,
    this.simulationOriginLongitude,
  });

  final String destinationName;
  final double destinationLatitude;
  final double destinationLongitude;
  final String routeToken;
  final bool trafficEnabled;
  final bool voiceGuidanceEnabled;
  final bool vibrationEnabled;
  final VoidCallback onArrived;
  final void Function(double latitude, double longitude) onLocation;
  final void Function(
    double remainingDistanceMeters,
    double remainingTimeSeconds,
    navigation.TrafficDelaySeverity traffic,
  )
  onProgress;
  final ValueChanged<String?> onStatus;
  final ValueChanged<double>? onCameraBearingChanged;
  final List<NavigationMemberPin> memberPins;
  final double? simulationOriginLatitude;
  final double? simulationOriginLongitude;

  @override
  State<NativeNavigationMap> createState() => NativeNavigationMapState();
}

class NativeNavigationMapState extends State<NativeNavigationMap> {
  static const double _compactBottomInset = 142;
  static const double _expandedBottomInset = 278;
  static const double _recommendationBottomInset = 420;

  navigation.GoogleNavigationViewController? _controller;
  StreamSubscription<navigation.OnArrivalEvent>? _arrivalSubscription;
  StreamSubscription<navigation.RoadSnappedLocationUpdatedEvent>?
  _locationSubscription;
  StreamSubscription<navigation.RemainingTimeOrDistanceChangedEvent>?
  _progressSubscription;
  bool _bottomPanelExpanded = false;
  bool _recommendationPanelVisible = false;
  StreamSubscription<navigation.GpsAvailabilityChangeEvent>? _gpsSubscription;
  Timer? _routeRetryTimer;
  bool _sessionInitialized = false;
  bool _hasLocation = false;
  bool _gpsValidForNavigation = false;
  int _locationSamples = 0;
  bool _routeStarted = false;
  bool _settingDestination = false;
  bool _destinationPending = false;
  bool _simulationRunning = false;
  bool _closing = false;
  int _routeAttempt = 0;
  String? _startupMessage;
  List<navigation.Marker> _memberMarkers = [];
  final Map<int, navigation.ImageDescriptor> _memberIcons = {};
  bool _updatingMembers = false;
  String _memberSignature = '';

  Future<navigation.ImageDescriptor> _countIcon(int count) async {
    if (_memberIcons[count] != null) return _memberIcons[count]!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (count > 1) {
      canvas.drawCircle(
        const Offset(34, 24),
        21,
        Paint()..color = const Color(0xffa8c4ff),
      );
    }
    canvas.drawCircle(const Offset(26, 32), 23, Paint()..color = Colors.white);
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
    final icon = await navigation.registerBitmapImage(
      bitmap: bytes!,
      width: 40,
      height: 40,
    );
    _memberIcons[count] = icon;
    return icon;
  }

  Future<void> _updateMemberPins() async {
    if (_controller == null || _closing || _updatingMembers) return;
    _updatingMembers = true;
    try {
      final pins = widget.memberPins;
      final signature = pins
          .map(
            (p) =>
                '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)},${p.names.join(',')}',
          )
          .join(';');
      if (signature == _memberSignature) return;
      final options = <navigation.MarkerOptions>[];
      for (final pin in pins) {
        options.add(
          navigation.MarkerOptions(
            position: navigation.LatLng(
              latitude: pin.latitude,
              longitude: pin.longitude,
            ),
            icon: await _countIcon(pin.names.length),
            zIndex: 10,
            infoWindow: navigation.InfoWindow(
              title:
                  '${pin.names.length} traveller${pin.names.length == 1 ? '' : 's'}',
              snippet: pin.names.join(', '),
            ),
          ),
        );
      }
      if (_closing) return;
      if (_memberMarkers.isNotEmpty) {
        await _controller!.removeMarkers(_memberMarkers);
      }
      _memberMarkers = (await _controller!.addMarkers(
        options,
      )).whereType<navigation.Marker>().toList();
      _memberSignature = signature;
    } catch (error) {
      if (!_closing) widget.onStatus('Could not update traveller pins: $error');
    } finally {
      _updatingMembers = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) navigationExperienceActive.value = true;
    });
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant NativeNavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_updateMemberPins());
    if (oldWidget.trafficEnabled != widget.trafficEnabled) {
      unawaited(_controller?.settings.setTrafficEnabled(widget.trafficEnabled));
    }
    if (oldWidget.voiceGuidanceEnabled != widget.voiceGuidanceEnabled ||
        oldWidget.vibrationEnabled != widget.vibrationEnabled) {
      unawaited(_applyAudioGuidanceSettings());
    }
    if (oldWidget.destinationLatitude != widget.destinationLatitude ||
        oldWidget.destinationLongitude != widget.destinationLongitude ||
        oldWidget.destinationName != widget.destinationName ||
        oldWidget.routeToken != widget.routeToken) {
      _routeRetryTimer?.cancel();
      _routeStarted = false;
      if (_hasLocation) unawaited(_setDestinationAndStart());
    }
  }

  Future<void> _initialize() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      _fail('Google turn-by-turn navigation is available on Android and iOS.');
      return;
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _fail('Turn on location services to start navigation.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _fail('Location permission is required to start navigation.');
        return;
      }

      var termsAccepted =
          await navigation.GoogleMapsNavigator.areTermsAccepted();
      if (!termsAccepted) {
        termsAccepted =
            await navigation.GoogleMapsNavigator.showTermsAndConditionsDialog(
              'ohMY navigation',
              'ohMY',
              uiParams: const navigation.TermsAndConditionsUIParams(
                backgroundColor: Colors.white,
                titleColor: Color(0xff3266cc),
                mainTextColor: Color(0xff14213d),
                acceptButtonTextColor: Color(0xff3266cc),
                cancelButtonTextColor: Color(0xff68748b),
              ),
            );
      }
      if (!termsAccepted) {
        _fail('Accept Google Navigation terms to start the journey.');
        return;
      }

      await navigation.GoogleMapsNavigator.initializeNavigationSession(
        taskRemovedBehavior: navigation.TaskRemovedBehavior.quitService,
      );
      _sessionInitialized = true;
      _arrivalSubscription =
          navigation.GoogleMapsNavigator.setOnArrivalListener((event) {
            if (!_closing) widget.onArrived();
          });
      _progressSubscription =
          navigation
              .GoogleMapsNavigator.setOnRemainingTimeOrDistanceChangedListener(
            (event) => widget.onProgress(
              event.remainingDistance,
              event.remainingTime,
              event.delaySeverity,
            ),
            remainingTimeThresholdSeconds: 15,
            remainingDistanceThresholdMeters: 25,
          );
      if (defaultTargetPlatform == TargetPlatform.android) {
        _gpsSubscription =
            await navigation
                .GoogleMapsNavigator.setOnGpsAvailabilityChangeListener((
              event,
            ) {
              _gpsValidForNavigation = event.isGpsValidForNavigation;
              if (_gpsValidForNavigation &&
                  _hasLocation &&
                  !_routeStarted &&
                  _controller != null) {
                unawaited(_setDestinationAndStart());
              }
            });
      }
      _locationSubscription =
          await navigation
              .GoogleMapsNavigator.setRoadSnappedLocationUpdatedListener((
            event,
          ) {
            _hasLocation = true;
            _locationSamples++;
            widget.onLocation(
              event.location.latitude,
              event.location.longitude,
            );
            if (!_routeStarted &&
                _controller != null &&
                _routeRetryTimer?.isActive != true &&
                (defaultTargetPlatform != TargetPlatform.android ||
                    _gpsValidForNavigation ||
                    _locationSamples >= 2)) {
              unawaited(_setDestinationAndStart());
            }
          });
      if (mounted) setState(() {});
      if (navigationSimulationEnabled &&
          widget.simulationOriginLatitude != null &&
          widget.simulationOriginLongitude != null) {
        await navigation.GoogleMapsNavigator.simulator.setUserLocation(
          navigation.LatLng(
            latitude: widget.simulationOriginLatitude!,
            longitude: widget.simulationOriginLongitude!,
          ),
        );
        _hasLocation = true;
        _gpsValidForNavigation = true;
        if (_controller != null) await _setDestinationAndStart();
      }
    } on navigation.SessionInitializationException catch (error) {
      _fail('Navigation could not start: ${error.code.name}.');
    } catch (error) {
      _fail(_friendlyError(error));
    }
  }

  Future<void> _onViewCreated(
    navigation.GoogleNavigationViewController controller,
  ) async {
    _controller = controller;
    unawaited(_updateMemberPins());
    try {
      await controller.setMyLocationEnabled(true);
      await controller.settings.setTrafficEnabled(widget.trafficEnabled);
      await controller.settings.setCompassEnabled(false);
      await controller.setBuildingsEnabled(false);
      await controller.setIndoorEnabled(false);
      await controller.setNavigationUIEnabled(true);
      await controller.setNavigationFooterEnabled(false);
      await controller.setTrafficPromptsEnabled(false);
      await controller.setTrafficIncidentCardsEnabled(false);
      await controller.setReportIncidentButtonEnabled(false);
      await controller.setRecenterButtonEnabled(false);
      await controller.settings.setMyLocationButtonEnabled(false);
      await controller.setPadding(
        const EdgeInsets.only(bottom: _compactBottomInset),
      );
      if (_hasLocation &&
          (defaultTargetPlatform != TargetPlatform.android ||
              _gpsValidForNavigation ||
              _locationSamples >= 2)) {
        await _setDestinationAndStart();
      }
    } catch (error) {
      if (!_closing) _fail(_friendlyError(error));
    }
  }

  Future<void> _setDestinationAndStart() async {
    if (_closing || !_sessionInitialized || _controller == null) return;
    if (_settingDestination) {
      _destinationPending = true;
      return;
    }
    _settingDestination = true;
    _routeStarted = true;
    if (mounted) setState(() => _startupMessage = 'Calculating route…');
    try {
      if (_simulationRunning) {
        await navigation.GoogleMapsNavigator.simulator.removeUserLocation();
        _simulationRunning = false;
      }
      if (navigationSimulationEnabled &&
          widget.simulationOriginLatitude != null &&
          widget.simulationOriginLongitude != null) {
        await navigation.GoogleMapsNavigator.simulator.setUserLocation(
          navigation.LatLng(
            latitude: widget.simulationOriginLatitude!,
            longitude: widget.simulationOriginLongitude!,
          ),
        );
      }
      final status = await navigation.GoogleMapsNavigator.setDestinations(
        navigation.Destinations(
          waypoints: [
            navigation.NavigationWaypoint.withLatLngTarget(
              title: widget.destinationName,
              target: navigation.LatLng(
                latitude: widget.destinationLatitude,
                longitude: widget.destinationLongitude,
              ),
            ),
          ],
          displayOptions: navigation.NavigationDisplayOptions(
            showDestinationMarkers: true,
            showStopSigns: true,
            showTrafficLights: true,
          ),
          routeTokenOptions: widget.routeToken.isEmpty
              ? null
              : navigation.RouteTokenOptions(
                  routeToken: widget.routeToken,
                  travelMode: navigation.NavigationTravelMode.driving,
                ),
          routingOptions: widget.routeToken.isEmpty
              ? navigation.RoutingOptions(
                  travelMode: navigation.NavigationTravelMode.driving,
                )
              : null,
        ),
      );
      if (status != navigation.NavigationRouteStatus.statusOk) {
        if ((status == navigation.NavigationRouteStatus.locationUnavailable ||
                status == navigation.NavigationRouteStatus.locationUnknown) &&
            !_closing) {
          _routeStarted = false;
          if (mounted) {
            setState(() {
              _startupMessage =
                  'Improving GPS accuracy before calculating the route…';
            });
          }
          widget.onStatus(
            'Improving GPS accuracy before calculating the route…',
          );
          _scheduleRouteRetry();
          return;
        }
        if (status == navigation.NavigationRouteStatus.networkError &&
            _routeAttempt < 2 &&
            !_closing) {
          _routeAttempt++;
          if (mounted) {
            setState(() {
              _startupMessage =
                  'Connection is slow. Retrying route (${_routeAttempt + 1}/3)…';
            });
          }
          await Future<void>.delayed(Duration(seconds: _routeAttempt * 2));
          if (!_closing) {
            _routeStarted = false;
            await _setDestinationAndStart();
          }
          return;
        }
        _routeStarted = false;
        _fail(_routeError(status));
        return;
      }
      await _applyAudioGuidanceSettings();
      await navigation.GoogleMapsNavigator.startGuidance();
      await _controller!.setNavigationUIEnabled(true);
      // The app supplies its own cancel/ETA/routes footer. Keep Google's
      // maneuver header, but prevent its native footer intercepting taps.
      await _controller!.setNavigationFooterEnabled(false);
      await _controller!.setTrafficPromptsEnabled(false);
      await _controller!.setTrafficIncidentCardsEnabled(false);
      await _controller!.setReportIncidentButtonEnabled(false);
      await _controller!.setRecenterButtonEnabled(false);
      await _controller!.followMyLocation(
        navigation.CameraPerspective.topDownHeadingUp,
      );
      if (navigationSimulationEnabled) {
        await navigation.GoogleMapsNavigator.simulator
            .simulateLocationsAlongExistingRouteWithOptions(
              navigation.SimulationOptions(
                speedMultiplier: navigationSimulationSpeed,
              ),
            );
        _simulationRunning = true;
      }
      _routeAttempt = 0;
      _routeRetryTimer?.cancel();
      widget.onStatus(null);
      if (mounted) setState(() => _startupMessage = null);
    } catch (error) {
      _routeStarted = false;
      _fail(_friendlyError(error));
    } finally {
      _settingDestination = false;
      if (_destinationPending && !_closing) {
        _destinationPending = false;
        unawaited(_setDestinationAndStart());
      }
    }
  }

  Future<void> recenter() async {
    try {
      await _controller?.followMyLocation(
        navigation.CameraPerspective.topDownHeadingUp,
        zoomLevel: 18,
      );
    } catch (error) {
      if (!_closing) _fail(_friendlyError(error));
    }
  }

  Future<void> showNorthUp() async {
    try {
      await _controller?.followMyLocation(
        navigation.CameraPerspective.topDownNorthUp,
        zoomLevel: 18,
      );
    } catch (error) {
      if (!_closing) _fail(_friendlyError(error));
    }
  }

  Future<void> setBottomPanelExpanded(bool expanded) async {
    _bottomPanelExpanded = expanded;
    await _applyViewportPadding();
  }

  Future<void> setRecommendationPanelVisible(bool visible) async {
    _recommendationPanelVisible = visible;
    try {
      await _applyViewportPadding();
      await _controller?.followMyLocation(
        navigation.CameraPerspective.topDownHeadingUp,
        zoomLevel: visible ? 17 : 18,
      );
    } catch (error) {
      if (!_closing) _fail(_friendlyError(error));
    }
  }

  Future<void> _applyViewportPadding() async {
    final bottom = _recommendationPanelVisible
        ? _recommendationBottomInset
        : _bottomPanelExpanded
        ? _expandedBottomInset
        : _compactBottomInset;
    await _controller?.setPadding(EdgeInsets.only(bottom: bottom));
  }

  Future<void> _applyAudioGuidanceSettings() async {
    if (!_sessionInitialized || _closing) return;
    try {
      await navigation.GoogleMapsNavigator.setAudioGuidance(
        navigation.NavigationAudioGuidanceSettings(
          isBluetoothAudioEnabled: true,
          isVibrationEnabled: widget.vibrationEnabled,
          guidanceType: widget.voiceGuidanceEnabled
              ? navigation.NavigationAudioGuidanceType.alertsAndGuidance
              : navigation.NavigationAudioGuidanceType.silent,
        ),
      );
    } catch (error) {
      if (!_closing) _fail(_friendlyError(error));
    }
  }

  void _scheduleRouteRetry() {
    _routeRetryTimer?.cancel();
    _routeRetryTimer = Timer(const Duration(seconds: 2), () {
      if (_closing || _routeStarted || !_hasLocation || _controller == null) {
        return;
      }
      unawaited(_setDestinationAndStart());
    });
  }

  /// Stops native guidance before the Flutter route is removed.
  Future<void> stop() => _cleanup();

  String _routeError(navigation.NavigationRouteStatus status) =>
      switch (status) {
        navigation.NavigationRouteStatus.locationUnavailable ||
        navigation.NavigationRouteStatus.locationUnknown =>
          'Waiting for an accurate GPS location. Please try again shortly.',
        navigation.NavigationRouteStatus.apiKeyNotAuthorized =>
          'The API key is not authorized for Google Navigation SDK.',
        navigation.NavigationRouteStatus.quotaExceeded ||
        navigation.NavigationRouteStatus.quotaCheckFailed =>
          'Google Navigation quota is unavailable.',
        navigation.NavigationRouteStatus.networkError =>
          'A network connection is required to calculate the route.',
        navigation.NavigationRouteStatus.routeNotFound =>
          'Google Navigation could not find a driving route.',
        _ => 'Google Navigation could not start (${status.name}).',
      };

  String _friendlyError(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  void _fail(String message) {
    widget.onStatus(message);
    if (mounted) setState(() => _startupMessage = message);
  }

  Future<void> _cleanup() async {
    if (_closing) return;
    _closing = true;
    for (final icon in _memberIcons.values) {
      unawaited(navigation.unregisterImage(icon));
    }
    _routeRetryTimer?.cancel();
    await _arrivalSubscription?.cancel();
    await _progressSubscription?.cancel();
    await _gpsSubscription?.cancel();
    await _locationSubscription?.cancel();
    if (_sessionInitialized) {
      try {
        if (_simulationRunning) {
          await navigation.GoogleMapsNavigator.simulator.removeUserLocation();
          _simulationRunning = false;
        }
        await navigation.GoogleMapsNavigator.cleanup();
      } catch (_) {
        // A native view may already have completed session cleanup.
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigationExperienceActive.value = false;
    });
    unawaited(_cleanup());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sessionInitialized) {
      return ColoredBox(
        color: const Color(0xffeef3fb),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const WauLoadingIndicator(size: 58),
                const SizedBox(height: 16),
                Text(
                  _startupMessage ?? 'Starting Google Navigation…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xff14213d)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        navigation.GoogleMapsNavigationView(
          onViewCreated: _onViewCreated,
          onCameraMove: (position) =>
              widget.onCameraBearingChanged?.call(position.bearing),
          initialNavigationUIEnabledPreference:
              navigation.NavigationUIEnabledPreference.automatic,
          initialMapType: navigation.MapType.normal,
          initialMapToolbarEnabled: false,
          initialZoomControlsEnabled: false,
          initialTiltGesturesEnabled: false,
          initialForceNightMode: navigation.NavigationForceNightMode.forceDay,
          initialPadding: const EdgeInsets.only(bottom: _compactBottomInset),
        ),
        if (_startupMessage != null)
          Positioned(
            left: 24,
            right: 24,
            top: MediaQuery.paddingOf(context).top + 88,
            child: Material(
              elevation: 5,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_startupMessage!, textAlign: TextAlign.center),
              ),
            ),
          ),
      ],
    );
  }
}
