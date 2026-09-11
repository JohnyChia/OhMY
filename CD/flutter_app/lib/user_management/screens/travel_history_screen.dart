import 'package:flutter/material.dart';
import 'package:community_discovery/community_discovery.dart';

import '../models/travel_history_entry.dart';
import '../services/travel_history_service.dart';

const _blue = Color(0xFF2E60C4);
const _ink = Color(0xFF17243D);
const _muted = Color(0xFF536681);
const _border = Color(0xFFCCD9EF);

enum _Filter { all, solo, group }

class TravelHistoryScreen extends StatefulWidget {
  const TravelHistoryScreen({super.key, this.communityController});

  final CommunityController? communityController;

  @override
  State<TravelHistoryScreen> createState() => _TravelHistoryScreenState();
}

class _TravelHistoryScreenState extends State<TravelHistoryScreen> {
  final _service = TravelHistoryService();
  late Future<List<TravelHistoryEntry>> _history;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _history = _service.fetchCompletedTrips();
  }

  Future<void> _refresh() async {
    final next = _service.fetchCompletedTrips();
    setState(() => _history = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _appBar(context, 'Travel history'),
      body: FutureBuilder<List<TravelHistoryEntry>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is TravelHistoryFailure
                ? (snapshot.error! as TravelHistoryFailure).message
                : 'Your completed trips could not be loaded.';
            return _Message(
              title: 'Could not load history',
              message: message,
              actionLabel: 'Try again',
              onAction: _refresh,
            );
          }

          final trips = snapshot.data ?? const [];
          if (trips.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: const CustomScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _EmptyPanel(),
                    ),
                  ),
                  SliverFillRemaining(hasScrollBody: false, child: SizedBox()),
                ],
              ),
            );
          }

          final visible = trips
              .where((trip) {
                return _filter == _Filter.all ||
                    (_filter == _Filter.solo &&
                        trip.type == TravelHistoryType.solo) ||
                    (_filter == _Filter.group &&
                        trip.type == TravelHistoryType.group);
              })
              .toList(growable: false);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                const _ReadOnlyNote(),
                const SizedBox(height: 12),
                _HistorySummary(trips: trips),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    _FilterButton(
                      label: 'All',
                      selected: _filter == _Filter.all,
                      onTap: () => setState(() => _filter = _Filter.all),
                    ),
                    _FilterButton(
                      label: 'Solo',
                      selected: _filter == _Filter.solo,
                      onTap: () => setState(() => _filter = _Filter.solo),
                    ),
                    _FilterButton(
                      label: 'Group',
                      selected: _filter == _Filter.group,
                      onTap: () => setState(() => _filter = _Filter.group),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 36),
                    child: Text(
                      'No completed trips match this filter.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted),
                    ),
                  )
                else
                  ...visible.map(
                    (trip) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        children: [
                          _TripCard(
                            trip: trip,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => TravelHistoryDetailsScreen(
                                  trip: trip,
                                  communityController:
                                      widget.communityController,
                                ),
                              ),
                            ),
                          ),
                          if (trip.canShareToCommunity &&
                              widget.communityController != null) ...[
                            const SizedBox(height: 6),
                            _CommunityPostAction(
                              trip: trip,
                              controller: widget.communityController!,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class TravelHistoryDetailsScreen extends StatelessWidget {
  const TravelHistoryDetailsScreen({
    super.key,
    required this.trip,
    this.communityController,
  });

  final TravelHistoryEntry trip;
  final CommunityController? communityController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _appBar(context, 'Trip details'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          _TripCard(trip: trip),
          if (trip.canShareToCommunity && communityController != null) ...[
            const SizedBox(height: 8),
            _CommunityPostAction(trip: trip, controller: communityController!),
          ],
          const SizedBox(height: 10),
          _Metrics(
            values: [
              ('${trip.stops.length}', 'Stops'),
              ('${_distance(trip.distanceKm)} km', 'Distance'),
              (_duration(trip.durationMinutes), 'Duration'),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Journey itinerary', style: TextStyle(color: _ink)),
          const SizedBox(height: 9),
          _ItineraryPanel(trip: trip),
          const SizedBox(height: 12),
          const Text('Trip information', style: TextStyle(color: _ink)),
          const SizedBox(height: 9),
          _InformationPanel(trip: trip),
        ],
      ),
    );
  }
}

class _CommunityPostAction extends StatefulWidget {
  const _CommunityPostAction({required this.trip, required this.controller});

  final TravelHistoryEntry trip;
  final CommunityController controller;

  @override
  State<_CommunityPostAction> createState() => _CommunityPostActionState();
}

class _CommunityPostActionState extends State<_CommunityPostAction> {
  late Future<CommunityPost?> _post;

  @override
  void initState() {
    super.initState();
    _post = widget.controller.getPostForHistoryEntry(widget.trip.id);
  }

  CompletedTrip get _communityTrip => CompletedTrip(
    id: widget.trip.id,
    title: widget.trip.title,
    locationName: widget.trip.destination,
    attractionName: widget.trip.destination,
    completedAt: widget.trip.completedAt,
  );

  Future<void> _open() async {
    await openTripHistoryPostAction(
      context,
      controller: widget.controller,
      historyEntry: _communityTrip,
    );
    if (mounted) {
      setState(
        () => _post = widget.controller.getPostForHistoryEntry(widget.trip.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CommunityPost?>(
    future: _post,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 42,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      if (snapshot.hasError) {
        return OutlinedButton.icon(
          onPressed: () => setState(
            () => _post = widget.controller.getPostForHistoryEntry(
              widget.trip.id,
            ),
          ),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry Community'),
        );
      }
      return SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: _open,
          icon: Icon(
            snapshot.data == null ? Icons.add_photo_alternate : Icons.edit,
          ),
          label: Text(snapshot.data == null ? 'Create post' : 'Edit post'),
        ),
      );
    },
  );
}

PreferredSizeWidget _appBar(BuildContext context, String title) {
  return AppBar(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    title: Text(title, style: const TextStyle(color: _ink, fontSize: 22)),
    leadingWidth: 80,
    leading: TextButton(
      onPressed: () => Navigator.maybePop(context),
      child: const Text(
        '‹  Back',
        style: TextStyle(color: _blue, fontSize: 13),
      ),
    ),
  );
}

class _ReadOnlyNote extends StatelessWidget {
  const _ReadOnlyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Automatically recorded from completed journeys — history cannot be edited.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 10),
      ),
    );
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.trips});

  final List<TravelHistoryEntry> trips;

  @override
  Widget build(BuildContext context) {
    final destinations = trips
        .map((trip) => trip.destination.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .length;
    final distance = trips.fold<double>(
      0,
      (sum, trip) => sum + trip.distanceKm,
    );
    return _Metrics(
      values: [
        ('${trips.length}', 'Trips'),
        ('$destinations', 'Destinations'),
        ('${_distance(distance)} km', 'Travelled'),
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.values});

  final List<(String, String)> values;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFC5D6F5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: values
            .map(
              (value) => Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value.$1,
                      maxLines: 1,
                      style: const TextStyle(color: _blue, fontSize: 18),
                    ),
                    Text(
                      value.$2,
                      style: const TextStyle(
                        color: Color(0xFF62708A),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 28,
        constraints: const BoxConstraints(minWidth: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _blue : const Color(0xFFF3F6FC),
          border: Border.all(color: selected ? _blue : _border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _muted,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, this.onTap});

  final TravelHistoryEntry trip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isGroup = trip.type == TravelHistoryType.group;
    final details = [
      '${trip.stops.length} ${trip.stops.length == 1 ? 'stop' : 'stops'}',
      '${_distance(trip.distanceKm)} km',
      if (trip.tags.isNotEmpty) trip.tags.take(2).join(' + '),
    ].join('  •  ');
    return Material(
      color: isGroup ? const Color(0xFFF7F5FF) : const Color(0xFFEDF5FF),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: _border),
        borderRadius: BorderRadius.circular(15),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isGroup
                            ? 'Completed group trip'
                            : 'Completed solo trip',
                        style: TextStyle(
                          color: isGroup ? const Color(0xFF7656C9) : _blue,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      trip.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _ink, fontSize: 16),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${trip.destination}  •  ${_date(trip.completedAt.toLocal())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _blue, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(
                    '›',
                    style: TextStyle(color: Color(0xFF73819A), fontSize: 20),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItineraryPanel extends StatelessWidget {
  const _ItineraryPanel({required this.trip});

  final TravelHistoryEntry trip;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5FF),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: trip.stops.isEmpty
          ? const Center(
              child: Text(
                'Stop details were not recorded for this older trip.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            )
          : Column(
              children: trip.stops
                  .map((stop) {
                    final time = stop.visitedAt == null
                        ? '—'
                        : _time(stop.visitedAt!.toLocal());
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text(
                              time,
                              style: const TextStyle(color: _ink, fontSize: 11),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '•  ${stop.name}',
                              style: const TextStyle(color: _ink, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
    );
  }
}

class _InformationPanel extends StatelessWidget {
  const _InformationPanel({required this.trip});

  final TravelHistoryEntry trip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: _muted, fontSize: 10, height: 1.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Travel mode  •  ${trip.travelMode}'),
            Text(
              'Started  •  ${_time(trip.startedAt.toLocal())}'
              '     Completed  •  ${_time(trip.completedAt.toLocal())}',
            ),
            const Text('Recorded automatically from the completed journey'),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'No travel history yet\n'
        'Complete a journey to see visited places and trip details here.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 15, height: 1.2),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF62708A), height: 1.4),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

String _distance(double value) {
  if (value == 0) return '0';
  return value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
}

String _duration(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '${remainder}m';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}

String _time(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String _date(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}
