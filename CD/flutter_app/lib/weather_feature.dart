import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class WeatherReading {
  const WeatherReading({
    required this.timestamp,
    required this.temperatureC,
    required this.feelsLikeC,
    required this.condition,
    required this.description,
    required this.rainProbability,
    required this.humidity,
    required this.windSpeed,
  });
  final int timestamp;
  final double? temperatureC, feelsLikeC, windSpeed;
  final String condition, description;
  final int rainProbability;
  final int? humidity;

  factory WeatherReading.fromJson(Map<String, dynamic> json) => WeatherReading(
    timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    temperatureC: (json['temperatureC'] as num?)?.toDouble(),
    feelsLikeC: (json['feelsLikeC'] as num?)?.toDouble(),
    condition: json['condition']?.toString() ?? 'Unavailable',
    description: json['description']?.toString() ?? 'Unavailable',
    rainProbability: (json['rainProbability'] as num?)?.round() ?? 0,
    humidity: (json['humidity'] as num?)?.round(),
    windSpeed: (json['windSpeedMetresPerSecond'] as num?)?.toDouble(),
  );
}

class WeatherOverview {
  const WeatherOverview({
    required this.locationName,
    required this.current,
    required this.hourly,
    required this.timezoneOffsetSeconds,
  });
  final String locationName;
  final WeatherReading current;
  final List<WeatherReading> hourly;
  final int timezoneOffsetSeconds;

  factory WeatherOverview.fromJson(Map<String, dynamic> json) =>
      WeatherOverview(
        locationName: json['locationName']?.toString() ?? 'Current area',
        current: WeatherReading.fromJson(
          Map<String, dynamic>.from(json['current'] as Map? ?? const {}),
        ),
        hourly: (json['hourly'] as List? ?? const [])
            .map(
              (item) => WeatherReading.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
        timezoneOffsetSeconds:
            (json['timezoneOffsetSeconds'] as num?)?.round() ?? 0,
      );
}

class WeatherService {
  const WeatherService({required this.backend});
  final String backend;

  Future<WeatherOverview> getOverview(double latitude, double longitude) async {
    final uri = Uri.parse(
      '$backend/api/weather/overview',
    ).replace(queryParameters: {'lat': '$latitude', 'lon': '$longitude'});
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        json['details'] ?? json['error'] ?? 'Weather request failed.',
      );
    }
    return WeatherOverview.fromJson(
      Map<String, dynamic>.from(json['weather'] as Map),
    );
  }
}

IconData weatherIcon(String condition) {
  final value = condition.toLowerCase();
  if (value.contains('thunder')) return Icons.thunderstorm_rounded;
  if (value.contains('rain') || value.contains('drizzle')) {
    return Icons.water_drop_rounded;
  }
  if (value.contains('cloud')) return Icons.cloud_rounded;
  if (value.contains('clear') || value.contains('sunny')) {
    return Icons.wb_sunny_rounded;
  }
  if (value.contains('mist') ||
      value.contains('fog') ||
      value.contains('haze')) {
    return Icons.foggy;
  }
  return Icons.cloud_queue_rounded;
}

String weatherDescription(String description) {
  final cleaned = description.trim().replaceAll('_', ' ').toLowerCase();
  if (cleaned.isEmpty || cleaned == 'unavailable') return 'Weather unavailable';
  return '${cleaned[0].toUpperCase()}${cleaned.substring(1)}';
}

class WeatherBottomPanel extends StatelessWidget {
  const WeatherBottomPanel({
    super.key,
    required this.weather,
    required this.onTap,
    required this.onClose,
  });
  final WeatherOverview weather;
  final VoidCallback onTap, onClose;

  @override
  Widget build(BuildContext context) {
    final current = weather.current;
    return Material(
      elevation: 14,
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xffedf4ff),
                child: Icon(
                  weatherIcon(current.condition),
                  size: 34,
                  color: const Color(0xff3266cc),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      weather.locationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${weatherDescription(current.description)}  •  ${current.temperatureC?.round() ?? '--'}°C',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Rain probability ${current.rainProbability}%',
                      style: const TextStyle(color: Color(0xff68748b)),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
                  const Icon(Icons.chevron_right, color: Color(0xff3266cc)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WeatherDetailPage extends StatelessWidget {
  const WeatherDetailPage({super.key, required this.weather});
  final WeatherOverview weather;

  String hour(int timestamp) {
    final time = DateTime.fromMillisecondsSinceEpoch(
      timestamp * 1000,
      isUtc: true,
    ).add(Duration(seconds: weather.timezoneOffsetSeconds));
    final value = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return '$value:${time.minute.toString().padLeft(2, '0')} ${time.hour >= 12 ? 'PM' : 'AM'}';
  }

  Widget metric(String label, String value) => Expanded(
    child: Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Color(0xff68748b))),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final current = weather.current;
    return Scaffold(
      backgroundColor: const Color(0xfff5f8fe),
      appBar: AppBar(
        title: const Text('Weather'),
        backgroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            elevation: 0,
            color: const Color(0xff3266cc),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    weather.locationName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Icon(
                    weatherIcon(current.condition),
                    color: Colors.white,
                    size: 64,
                  ),
                  Text(
                    '${current.temperatureC?.round() ?? '--'}°C',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    weatherDescription(current.description),
                    style: const TextStyle(color: Colors.white, fontSize: 17),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              metric('Feels like', '${current.feelsLikeC?.round() ?? '--'}°C'),
              metric('Rain', '${current.rainProbability}%'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              metric('Humidity', '${current.humidity ?? '--'}%'),
              metric(
                'Wind',
                current.windSpeed == null
                    ? '--'
                    : '${current.windSpeed!.toStringAsFixed(1)} m/s',
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Next few hours',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              Text(
                'Swipe left for more →',
                style: TextStyle(fontSize: 11, color: Color(0xff68748b)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: weather.hourly.isEmpty
                ? const Center(child: Text('Hourly forecast unavailable.'))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: weather.hourly.length,
                    separatorBuilder: (_, index) => const SizedBox(width: 10),
                    itemBuilder: (_, index) {
                      final item = weather.hourly[index];
                      return Container(
                        width: 108,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              hour(item.timestamp),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Icon(
                              weatherIcon(item.condition),
                              color: const Color(0xff3266cc),
                              size: 30,
                            ),
                            Text(
                              '${item.temperatureC?.round() ?? '--'}°C',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${item.rainProbability}% rain',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xff68748b),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
