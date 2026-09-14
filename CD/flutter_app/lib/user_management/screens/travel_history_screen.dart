import 'package:flutter/material.dart';
import 'package:community_discovery/community_discovery.dart';
import 'package:flutter_app/shared/widgets/wau_loading_indicator.dart';

import '../models/travel_history_entry.dart';
import '../services/travel_history_service.dart';
import '../widgets/profile_tab_background.dart';

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
      backgroundColor: const Color(0xFFFFFBF5),
      extendBodyBehindAppBar: true,
      appBar: _appBar(context, 'Travel history'),
      body: ProfileTabBackground(
        child: FutureBuilder<List<TravelHistoryEntry>>(
          future: _history,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: WauLoadingIndicator(size: 58));
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
              return WauRefreshIndicator(
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
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: SizedBox(),
                    ),
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

            return WauRefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  const _ReadOnlyNote(),
                  const SizedBox(height: 12),
                  _HistorySummary(trips: trips),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _FilterButton(
                          label: 'All',
                          selected: _filter == _Filter.all,
                          onTap: () => setState(() => _filter = _Filter.all),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FilterButton(
                          label: 'Solo',
                          selected: _filter == _Filter.solo,
                          onTap: () => setState(() => _filter = _Filter.solo),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FilterButton(
                          label: 'Group',
                          selected: _filter == _Filter.group,
                          onTap: () => setState(() => _filter = _Filter.group),
                        ),
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
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
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
    final isSolo = trip.type == TravelHistoryType.solo;
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      extendBodyBehindAppBar: true,
      appBar: _appBar(context, 'Trip details'),
      body: ProfileTabBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            _TripCard(trip: trip),
            if (trip.canShareToCommunity && communityController != null) ...[
              const SizedBox(height: 8),
              _CommunityPostAction(
                trip: trip,
                controller: communityController!,
              ),
            ],
            const SizedBox(height: 10),
            _Metrics(
              values: [
                if (!isSolo) ('${trip.stops.length}', 'Stops'),
                ('${_distance(trip.distanceKm)} km', 'Distance'),
                (_duration(trip.durationMinutes), 'Duration'),
              ],
            ),
            if (!isSolo) ...[
              const SizedBox(height: 18),
              const Text(
                'Journey itinerary',
                style: TextStyle(
                  color: Color(0xFF123A78),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 9),
              _ItineraryPanel(trip: trip),
            ],
            const SizedBox(height: 16),
            const Text(
              'Trip information',
              style: TextStyle(
                color: Color(0xFF123A78),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            _InformationPanel(trip: trip),
          ],
        ),
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
    final result = await openTripHistoryPostAction(
      context,
      controller: widget.controller,
      historyEntry: _communityTrip,
    );
    if (mounted) {
      setState(() {
        _post = result == PostEditorResult.deleted
            ? Future<CommunityPost?>.value(null)
            : widget.controller.getPostForHistoryEntry(widget.trip.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CommunityPost?>(
    future: _post,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 42,
          child: Center(child: WauLoadingIndicator(size: 22)),
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
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _blue,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            shape: const StadiumBorder(),
          ),
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
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: false,
    title: Text(
      title,
      style: const TextStyle(
        color: Color(0xFF123A78),
        fontWeight: FontWeight.w700,
      ),
    ),
    leading: IconButton(
      tooltip: 'Back',
      onPressed: () => Navigator.maybePop(context),
      icon: const Icon(Icons.arrow_back, color: _ink),
    ),
  );
}

class _ReadOnlyNote extends StatelessWidget {
  const _ReadOnlyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160D2F69),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: const Text(
        'Automatically recorded from completed journeys — history cannot be edited.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
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
      height: 68,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        border: Border.all(color: const Color(0xFFC5D6F5)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120D2F69),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
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
                      style: const TextStyle(
                        color: _blue,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      value.$2,
                      style: const TextStyle(
                        color: Color(0xFF62708A),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
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
        height: 36,
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
            color: selected ? Colors.white : _ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
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
      if (isGroup)
        '${trip.stops.length} ${trip.stops.length == 1 ? 'stop' : 'stops'}',
      '${_distance(trip.distanceKm)} km',
      if (trip.tags.isNotEmpty) trip.tags.take(2).join(' + '),
    ].join('  •  ');
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 1,
      shadowColor: const Color(0x220D2F69),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isGroup ? const Color(0xFFCFC7EF) : const Color(0xFFB9D0F5),
          width: 1.2,
        ),
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
                    if (isGroup) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0ECFF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Group Trip',
                          style: TextStyle(
                            color: Color(0xFF7656C9),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      trip.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF123A78),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${trip.destination}  •  ${_date(trip.completedAt.toLocal())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _blue,
                    size: 22,
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
        color: Colors.white.withValues(alpha: 0.96),
        border: Border.all(color: const Color(0xFFB9D0F5), width: 1.2),
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120D2F69),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: trip.stops.isEmpty
          ? const Center(
              child: Text(
                'Stop details were not recorded for this older trip.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
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
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '•  ${stop.name}',
                              style: const TextStyle(
                                color: Color(0xFF123A78),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
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
        color: Colors.white.withValues(alpha: 0.96),
        border: Border.all(color: const Color(0xFFB9D0F5), width: 1.2),
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120D2F69),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (trip.type == TravelHistoryType.group)
              Text('Travel mode  •  ${trip.travelMode}'),
            Text(
              'Started  •  ${_time(trip.startedAt.toLocal())}'
              '     Completed  •  ${_time(trip.completedAt.toLocal())}',
            ),
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
