import 'package:geolocator/geolocator.dart';

const navigationLocationSettings = LocationSettings(
  accuracy: LocationAccuracy.bestForNavigation,
  distanceFilter: 1,
);
