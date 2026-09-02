import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const blue = Color(0xff3266cc),
    ink = Color(0xff14213d),
    muted = Color(0xff68748b),
    soft = Color(0xffedf4ff);

class PlaceMapPage extends StatefulWidget {
  const PlaceMapPage({super.key});
  @override
  State<PlaceMapPage> createState() => _PlaceMapPageState();
}

class _PlaceMapPageState extends State<PlaceMapPage> {
  static String get backend {
    const fromEnv = String.fromEnvironment('BACKEND_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) return 'http://127.0.0.1:3000';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    } catch (_) {}
    return 'http://127.0.0.1:3000';
  }

  static const preferences = [
    'Museum',
    'Heritage',
    'Cultural Learning',
    'Nature',
    'Religious Heritage',
  ];
  final search = TextEditingController();
  final recommendationScroll = ScrollController();
  GoogleMapController? controller;
  MethodChannel? poiChannel;
  List<Map<String, dynamic>> results = [], recommendations = [];
  Map<String, dynamic>? selected;
  Set<Marker> markers = {};
  bool loading = false, showCarousel = false, bookmarked = false;
  String? message;

  String name(Map p) =>
      p['displayName']?['text']?.toString() ?? 'Selected place';
  String description(Map p) =>
      p['description']?.toString().trim().isNotEmpty == true
      ? p['description'].toString()
      : p['primaryTypeDisplayName'] != null
      ? '${p['primaryTypeDisplayName']} at ${p['formattedAddress'] ?? 'this location'}.'
      : 'Description unavailable.';
  List<String> tags(Map item) => [
    ...List<String>.from(item['analysis']?['generalTags'] ?? []),
    ...List<String>.from(item['analysis']?['culturalTags'] ?? []),
  ];
  String distance(Map p) {
    final v = p['routeDistanceKm'] ?? p['distanceKm'];
    return v is num ? '${v.toStringAsFixed(1)} km' : 'Distance unavailable';
  }

  String eta(Map p) {
    final v = p['etaMinutes'];
    return v is num
        ? '${p['etaEstimated'] == true ? '~' : ''}${v.round()} min'
        : 'ETA unavailable';
  }

  String? photo(Map p) {
    final n = p['photo']?['name']?.toString();
    return n == null
        ? null
        : '$backend/api/places/photo?name=${Uri.encodeQueryComponent(n)}';
  }

  Future<Map<String, dynamic>> post(String path, Map body) async {
    final r = await http.post(
      Uri.parse('$backend$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(data['error'] ?? 'Request failed');
    }
    return data;
  }

  Future<Position?> position() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition();
  }

  double km(Position a, Map b) {
    double rad(double n) => n * math.pi / 180;
    const r = 6371.0;
    final p1 = rad(a.latitude), p2 = rad((b['latitude'] as num).toDouble());
    final dp = p2 - p1,
        dl = rad((b['longitude'] as num).toDouble() - a.longitude);
    final x =
        math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return r * 2 * math.atan2(math.sqrt(x), math.sqrt(1 - x));
  }

  Future<void> runSearch() async {
    if (search.text.trim().isEmpty) return;
    setState(() {
      loading = true;
      results = [];
      showCarousel = false;
      message = 'Searching places…';
    });
    try {
      final d = await post('/api/places/search', {'query': search.text.trim()});
      if (mounted) {
        setState(() {
          results = List<Map<String, dynamic>>.from(d['places'] ?? []);
          message = results.isEmpty ? 'No places found.' : null;
        });
      }
    } catch (e) {
      fail(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> selectPlace(String id) async {
    setState(() {
      loading = true;
      results = [];
      showCarousel = false;
      message = 'Fetching reviews and assigning tags…';
    });
    try {
      final all = await Future.wait([
        post('/api/places/analyze', {'placeId': id}),
        position(),
      ]);
      final item = all[0] as Map<String, dynamic>, pos = all[1] as Position?;
      final p = item['place'] as Map<String, dynamic>;
      if (pos != null && p['location'] != null) {
        final d = km(pos, p['location']);
        p['distanceKm'] = d;
        p['etaMinutes'] = math.max(2, (d * 2).ceil());
        p['etaEstimated'] = true;
      }
      await choose(item, true);
    } catch (e) {
      fail(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> choose(Map<String, dynamic> item, bool create) async {
    final p = item['place'] as Map<String, dynamic>,
        l = p['location'] as Map<String, dynamic>;
    final target = LatLng(
      (l['latitude'] as num).toDouble(),
      (l['longitude'] as num).toDouble(),
    );
    setState(() {
      selected = item;
      bookmarked = false;
      message = null;
      if (create) {
        markers = {
          Marker(
            markerId: MarkerId(p['id'].toString()),
            position: target,
            onTap: () => setState(() => selected = item),
          ),
        };
      }
    });
    await controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
  }

  Future<void> nearby() async {
    setState(() {
      loading = true;
      selected = null;
      message = 'Discovering and tagging nearby places…';
    });
    try {
      final pos = await position();
      if (pos == null) throw Exception('Location permission is required.');
      final d = await post('/api/recommendations/nearby-tagged', {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'mode': 'preferences',
        'preferences': preferences,
      });
      final tagged = List<Map<String, dynamic>>.from(d['taggedPlaces'] ?? []),
          m = <Marker>{};
      final visiblePoints = <LatLng>[LatLng(pos.latitude, pos.longitude)];
      for (final item in tagged) {
        final p = item['place'] as Map<String, dynamic>,
            l = p['location'] as Map<String, dynamic>;
        final markerPosition = LatLng(
          (l['latitude'] as num).toDouble(),
          (l['longitude'] as num).toDouble(),
        );
        visiblePoints.add(markerPosition);
        m.add(
          Marker(
            markerId: MarkerId(p['id'].toString()),
            position: markerPosition,
            onTap: () => _selectTaggedMarker(item),
          ),
        );
      }
      if (mounted) {
        setState(() {
          recommendations = List<Map<String, dynamic>>.from(
            d['matchedPlaces'] ?? [],
          );
          markers = m;
          showCarousel = recommendations.isNotEmpty;
          message = recommendations.isEmpty ? 'No matches found.' : null;
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await _showNearbyArea(visiblePoints);
    } catch (e) {
      fail(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _showNearbyArea(List<LatLng> points) async {
    if (points.isEmpty || controller == null) return;
    if (points.length == 1) {
      await controller!.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 12),
      );
      return;
    }

    var south = points.first.latitude;
    var north = points.first.latitude;
    var west = points.first.longitude;
    var east = points.first.longitude;
    for (final point in points.skip(1)) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    await controller!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        72,
      ),
    );
  }

  void _selectTaggedMarker(Map<String, dynamic> item) {
    final placeId = item['place']?['id'];
    final index = recommendations.indexWhere(
      (candidate) => candidate['place']?['id'] == placeId,
    );
    setState(() {
      selected = index >= 0 ? recommendations[index] : item;
      showCarousel = true;
    });
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!recommendationScroll.hasClients) return;
      recommendationScroll.animateTo(
        index * 340.0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void fail(Object e) {
    if (mounted) {
      setState(() => message = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> directions(Map p) async {
    final u = p['googleMapsUri']?.toString();
    if (u != null) {
      await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
    }
  }

  void details(Map<String, dynamic> item) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PlaceDetailPage(
        item: item,
        backend: backend,
        onDirections: () => directions(item['place']),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: LatLng(3.139, 101.6869),
            zoom: 13,
          ),
          onMapCreated: (c) {
            controller = c;
            poiChannel = MethodChannel('ohmy/google_map_poi/${c.mapId}');
            poiChannel!.setMethodCallHandler((call) async {
              if (call.method != 'onPoiTap') return;
              final poi = Map<String, dynamic>.from(call.arguments as Map);
              final placeId = poi['placeId']?.toString();
              if (placeId != null && placeId.isNotEmpty) {
                await selectPlace(placeId);
              }
            });
          },
          markers: markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: blue,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'MY',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Material(
                    elevation: 5,
                    borderRadius: BorderRadius.circular(18),
                    child: TextField(
                      controller: search,
                      onSubmitted: (_) => runSearch(),
                      decoration: InputDecoration(
                        hintText: 'Search attractions…',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 17,
                          vertical: 14,
                        ),
                        suffixIcon: IconButton(
                          onPressed: runSearch,
                          icon: const Icon(Icons.search),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (results.isNotEmpty) resultList(),
        controls(),
        nearbyButton(),
        if (selected != null && !showCarousel) selectionPanel(),
        if (showCarousel) carousel(),
        if (loading)
          const Center(child: CircularProgressIndicator(color: blue)),
        if (message != null && !loading)
          Positioned(
            left: 70,
            right: 70,
            bottom: showCarousel ? 205 : 22,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget resultList() => Positioned(
    top: 82,
    left: 70,
    right: 16,
    child: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 330),
        child: ListView.builder(
          padding: const EdgeInsets.all(7),
          shrinkWrap: true,
          itemCount: results.length,
          itemBuilder: (_, i) {
            final p = results[i];
            return ListTile(
              dense: true,
              leading: Icon(
                p['isArea'] == true ? Icons.map_outlined : Icons.place,
                color: blue,
              ),
              title: Text(name(p), maxLines: 1),
              subtitle: Text(p['formattedAddress'] ?? '', maxLines: 2),
              onTap: p['isArea'] == true ? null : () => selectPlace(p['id']),
            );
          },
        ),
      ),
    ),
  );
  Widget controls() => Positioned(
    left: 16,
    bottom: showCarousel ? 202 : 20,
    child: Column(
      children: [
        mapButton(Icons.traffic, 'Traffic integration coming later'),
        const SizedBox(height: 9),
        mapButton(Icons.cloud, 'Weather integration coming later'),
      ],
    ),
  );
  Widget mapButton(IconData i, String m) => Material(
    elevation: 5,
    color: Colors.white,
    shape: const CircleBorder(),
    child: IconButton(
      color: blue,
      icon: Icon(i),
      onPressed: () => setState(() => message = m),
    ),
  );
  Widget nearbyButton() => Positioned(
    right: 16,
    bottom: showCarousel ? 202 : 20,
    child: FloatingActionButton.extended(
      heroTag: 'nearby',
      backgroundColor: blue,
      foregroundColor: Colors.white,
      onPressed: nearby,
      icon: const Icon(Icons.my_location),
      label: const Text('Nearby matches'),
    ),
  );

  Widget selectionPanel() {
    final item = selected!, p = item['place'] as Map<String, dynamic>;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Material(
        elevation: 12,
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => details(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => selected = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  description(p),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  '${eta(p)}  ·  ${distance(p)}',
                  style: const TextStyle(
                    color: blue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                tagRow(tags(item)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => directions(p),
                      icon: const Icon(Icons.directions),
                      label: const Text('Directions'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => bookmarked = !bookmarked),
                      icon: Icon(
                        bookmarked ? Icons.bookmark : Icons.bookmark_border,
                      ),
                      label: const Text('Bookmark'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget carousel() => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    height: 190,
    child: Material(
      elevation: 14,
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 0, 10),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Based on your preferences',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => showCarousel = false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: ListView.separated(
                controller: recommendationScroll,
                scrollDirection: Axis.horizontal,
                itemCount: recommendations.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (_, i) => recommendationCard(recommendations[i]),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget recommendationCard(Map<String, dynamic> item) {
    final p = item['place'] as Map<String, dynamic>;
    final img = photo(p);
    final isSelected = selected?['place']?['id'] == p['id'];
    return SizedBox(
      width: 330,
      child: Card(
        margin: EdgeInsets.zero,
        color: const Color(0xfff6f9ff),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: isSelected ? blue : const Color(0xffc9dcfb),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: () => details(item),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                if (img != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.network(
                      img,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (img != null) const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        description(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                      Text(
                        '${eta(p)} · ${distance(p)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      tagRow(tags(item)),
                      Row(
                        children: [
                          tiny(
                            Icons.directions,
                            'Directions',
                            () => directions(p),
                          ),
                          tiny(Icons.bookmark_border, 'Bookmark', () {}),
                        ],
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

  Widget tiny(IconData i, String s, VoidCallback f) => SizedBox(
    height: 27,
    child: TextButton.icon(
      onPressed: f,
      icon: Icon(i, size: 14),
      label: Text(s, style: const TextStyle(fontSize: 9)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
    ),
  );
  Widget tagRow(List<String> t) => SizedBox(
    height: 24,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final x in t.take(5))
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Chip(
              label: Text(x, style: const TextStyle(fontSize: 9)),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
        if (t.length > 5) const Text('…'),
      ],
    ),
  );
  @override
  void dispose() {
    search.dispose();
    recommendationScroll.dispose();
    poiChannel?.setMethodCallHandler(null);
    controller?.dispose();
    super.dispose();
  }
}

class PlaceDetailPage extends StatefulWidget {
  const PlaceDetailPage({
    super.key,
    required this.item,
    required this.backend,
    required this.onDirections,
  });
  final Map<String, dynamic> item;
  final String backend;
  final VoidCallback onDirections;
  @override
  State<PlaceDetailPage> createState() => _PlaceDetailPageState();
}

class _PlaceDetailPageState extends State<PlaceDetailPage> {
  bool saved = false;
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final p = widget.item['place'] as Map<String, dynamic>,
        a =
            widget.item['analysis'] as Map<String, dynamic>? ??
            <String, dynamic>{},
        t = [
          ...List<String>.from(a['generalTags'] ?? []),
          ...List<String>.from(a['culturalTags'] ?? []),
        ],
        photos = List<Map<String, dynamic>>.from(p['photos'] ?? []),
        n = p['displayName']?['text'] ?? 'Place details';
    return Scaffold(
      appBar: AppBar(
        title: Text(n, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: () => setState(() => saved = !saved),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: widget.onDirections,
          icon: const Icon(Icons.directions),
          label: const Text('Directions'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          if (photos.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 250,
                child: PageView.builder(
                  itemCount: math.min(5, photos.length),
                  onPageChanged: (v) => setState(() => page = v),
                  itemBuilder: (_, i) => Image.network(
                    '${widget.backend}/api/places/photo?name=${Uri.encodeQueryComponent(photos[i]['name'])}',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const _PhotoUnavailable(),
                  ),
                ),
              ),
            ),
            if (photos.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${page + 1} of ${math.min(5, photos.length)}',
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                    const Text(
                      'Swipe for more →',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
          ] else
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(20)),
              child: SizedBox(height: 250, child: _PhotoUnavailable()),
            ),
          const SizedBox(height: 18),
          const Text(
            'ABOUT THIS PLACE',
            style: TextStyle(
              color: blue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            n,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            p['description'] ??
                p['primaryTypeDisplayName'] ??
                'Description unavailable.',
            style: const TextStyle(color: muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          Text(
            p['formattedAddress'] ?? 'Address unavailable',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: metric(
                  'Estimated arrival',
                  p['etaMinutes'] is num
                      ? '${p['etaEstimated'] == true ? '~' : ''}${(p['etaMinutes'] as num).round()} min'
                      : 'Unavailable',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: metric(
                  'Distance',
                  p['distanceKm'] is num
                      ? '${(p['distanceKm'] as num).toStringAsFixed(1)} km'
                      : 'Unavailable',
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text('Tags', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: t
                .map(
                  (x) => Chip(
                    label: Text(x, style: const TextStyle(fontSize: 11)),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget metric(String l, String v) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: soft,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l, style: const TextStyle(fontSize: 10, color: muted)),
        const SizedBox(height: 5),
        Text(
          v,
          style: const TextStyle(
            color: blue,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _PhotoUnavailable extends StatelessWidget {
  const _PhotoUnavailable();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: const Color(0xfff4bc60),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.image_not_supported_outlined,
          size: 42,
          color: Color(0xff765521),
        ),
        SizedBox(height: 10),
        Text(
          'Picture unavailable',
          style: TextStyle(
            color: Color(0xff765521),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
