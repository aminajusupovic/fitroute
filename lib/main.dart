// ─────────────────────────────────────────────────────────────────────────────
// main.dart — FitRoute
// Entry point and all screens/widgets for the FitRoute app.
//
// Packages used:
//   geolocator        → gets the user's GPS coordinates
//   flutter_map       → displays the interactive OpenStreetMap map
//   latlong2          → LatLng coordinate model used by flutter_map
//   http              → makes HTTP requests to all third-party APIs
//
// Third-party APIs used (all free, no API key required):
//   Open-Meteo        → live weather data
//   OSRM              → snaps generated routes to real roads
//   Nominatim         → reverse geocodes GPS coords to a city name
//   OpenStreetMap     → map tile images shown inside flutter_map
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:http/http.dart' as http;

// App entry point
void main() {
  runApp(const FitRouteApp());
}

// ─── App Root ─────────────────────────────────────────────────────────────────

class FitRouteApp extends StatelessWidget {
  const FitRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitRoute',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6)),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
    );
  }
}

// ─── Shared App State ─────────────────────────────────────────────────────────
// A simple global state object that holds all data shared across screens.
// It includes a basic listener system so that when weather data arrives
// asynchronously, the InfoScreen can rebuild itself automatically.

class AppState {
  // User preferences
  String activity = 'Walk';
  int distance = 3;

  // Location — defaults to Dubrovnik if GPS fails
  double lat = 42.6507;
  double lng = 18.0944;
  String locationName = 'Tap to get location';
  bool hasLocation = false;

  // Weather data fetched from Open-Meteo API
  WeatherData? weather;

  // Route data fetched from OSRM API
  List<LatLng>? routePoints;
  double? routeDistanceKm;
  int? routeTimeMin;

  // Simple listener list — any widget can subscribe to be notified of changes
  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);

  // Call this after changing weather/location so subscribed widgets rebuild
  void notify() {
    for (final cb in List<VoidCallback>.from(_listeners)) {
      cb();
    }
  }
}

// Single global instance shared by all screens
final appState = AppState();

// ─── Data Models ──────────────────────────────────────────────────────────────

// Holds all weather data returned by the Open-Meteo API
class WeatherData {
  final double tempC; // Temperature in Celsius
  final int humidity; // Relative humidity %
  final double windKph; // Wind speed in km/h
  final int code; // WMO weather code (0 = clear, higher = worse)
  final List<HourlyForecast> forecast; // Morning/afternoon/evening forecast

  WeatherData({
    required this.tempC,
    required this.humidity,
    required this.windKph,
    required this.code,
    required this.forecast,
  });

  // Computed properties for display
  double get tempF => tempC * 9 / 5 + 32;
  int get windMph => (windKph * 0.621).round();

  // Maps WMO weather code to an emoji
  String get emoji {
    if (code == 0) return '☀️';
    if (code <= 3) return '⛅';
    if (code <= 48) return '🌫️';
    if (code <= 67) return '🌧️';
    if (code <= 77) return '❄️';
    if (code <= 82) return '🌦️';
    return '⛈️';
  }

  // Maps WMO weather code to a text label
  String get label {
    if (code == 0) return 'Clear sky';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 48) return 'Foggy';
    if (code <= 67) return 'Rainy';
    if (code <= 77) return 'Snowy';
    if (code <= 82) return 'Showers';
    return 'Thunderstorm';
  }

  // Returns true when conditions are safe and comfortable for exercise
  bool get isGoodForActivity =>
      code <= 3 && tempC > 5 && tempC < 35 && windKph < 40;
}

// Holds one row of the hourly forecast (morning / afternoon / evening)
class HourlyForecast {
  final String label; // e.g. "Morning"
  final double tempF; // Temperature in Fahrenheit
  final String emoji; // Weather emoji

  HourlyForecast({
    required this.label,
    required this.tempF,
    required this.emoji,
  });
}

// ─── Main Navigation ──────────────────────────────────────────────────────────
// Holds the bottom navigation bar and switches between the 3 screens.

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  // Called by HomeScreen after a route is generated — jumps to Route tab
  void _onRouteGenerated() => setState(() => _selectedIndex = 1);

  // Called by RouteScreen "Generate Another" button — goes back to Home
  void _onGenerateAnother() => setState(() => _selectedIndex = 0);

  // Called by HomeScreen when location/weather updates — rebuilds nav
  void _onStateChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps all 3 screens alive so state isn't lost on tab switch
    final pages = [
      HomeScreen(
        onRouteGenerated: _onRouteGenerated,
        onStateChanged: _onStateChanged,
      ),
      RouteScreen(onGenerateAnother: _onGenerateAnother),
      const InfoScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black12,
        elevation: 8,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Route',
          ),
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny),
            label: 'Weather',
          ),
        ],
      ),
    );
  }
}

// ─── Home Screen ──────────────────────────────────────────────────────────────
// Lets the user pick activity type and distance, then generate a route.

class HomeScreen extends StatefulWidget {
  final VoidCallback onRouteGenerated;
  final VoidCallback onStateChanged;

  const HomeScreen({
    super.key,
    required this.onRouteGenerated,
    required this.onStateChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _generatingRoute = false;

  // Available distance options shown as circles
  final List<int> _distances = [1, 3, 5, 8, 10];

  // ── Location ──────────────────────────────────────────────────────────────
  // Uses the Geolocator package to get GPS coordinates, then calls
  // Nominatim (OpenStreetMap reverse geocoding API) to get the city name.
  // After location is found, weather is fetched in the background.
  Future<void> _getLocation() async {
    setState(() => appState.locationName = 'Getting location...');

    try {
      // Check if location services are enabled on the device
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => appState.locationName = 'Location services are off');
        return;
      }

      // Check/request location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => appState.locationName = 'Location permission denied');
        return;
      }

      // Get actual GPS coordinates from device
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      appState.lat = position.latitude;
      appState.lng = position.longitude;
      appState.hasLocation = true;

      // Reverse geocode: convert lat/lng → city name using Nominatim API
      try {
        final r = await http.get(
          Uri.parse(
            'https://nominatim.openstreetmap.org/reverse'
            '?lat=${appState.lat}&lon=${appState.lng}&format=json',
          ),
          headers: {'User-Agent': 'FitRouteApp/1.0'},
        );
        if (r.statusCode == 200) {
          final d = json.decode(r.body);
          final address = d['address'];
          // Try city → town → village → county as fallback chain
          final city =
              address['city'] ??
              address['town'] ??
              address['village'] ??
              address['county'] ??
              'Your Location';
          final country = address['country'] ?? '';
          appState.locationName = country.isNotEmpty ? '$city, $country' : city;
        }
      } catch (_) {
        // If reverse geocoding fails, just show raw coordinates
        appState.locationName =
            '${appState.lat.toStringAsFixed(4)}, ${appState.lng.toStringAsFixed(4)}';
      }

      setState(() {});
      widget.onStateChanged();

      // Fetch weather in the background — when it arrives, notify all listeners
      // including InfoScreen so it rebuilds and shows the weather card
      WeatherService.fetch(appState.lat, appState.lng).then((w) {
        if (w != null) {
          appState.weather = w;
          appState.notify(); // triggers InfoScreen to rebuild
          widget.onStateChanged();
        }
      });
    } catch (_) {
      // GPS failed — fall back to Dubrovnik as default location
      appState.lat = 42.6507;
      appState.lng = 18.0944;
      appState.locationName = 'Dubrovnik, Croatia';
      appState.hasLocation = true;
      setState(() {});

      WeatherService.fetch(appState.lat, appState.lng).then((w) {
        if (w != null) {
          appState.weather = w;
          appState.notify();
          widget.onStateChanged();
        }
      });
    }
  }

  // ── Route Generation ──────────────────────────────────────────────────────
  // Step 1: RouteGenerator.generate() creates circular waypoints sized to
  //         match the user's selected distance (using circumference formula).
  // Step 2: RouteGenerator.snapToRoads() sends those waypoints to the OSRM
  //         routing API which snaps them to real walkable streets.
  // Step 3: If OSRM returns a wildly wrong distance it is rejected and the
  //         raw generated points are used as fallback.
  Future<void> _generateRoute() async {
    setState(() => _generatingRoute = true);

    try {
      final targetKm = appState.distance.toDouble();

      // Generate circular waypoints whose total perimeter ≈ targetKm
      final points = RouteGenerator.generate(
        appState.lat,
        appState.lng,
        targetKm,
      );

      // Snap waypoints to real roads via OSRM API
      final result = await RouteGenerator.snapToRoads(points, targetKm);

      if (result != null) {
        // OSRM succeeded and distance is reasonable — use snapped route
        appState.routePoints = result.points;
        appState.routeDistanceKm = result.distanceKm;
        // Walk pace ≈ 12 min/km, jog pace ≈ 7 min/km
        appState.routeTimeMin = appState.activity == 'Walk'
            ? (result.distanceKm * 12).round()
            : (result.distanceKm * 7).round();
      } else {
        // OSRM failed or returned bad data — use raw generated points
        appState.routePoints = points;
        appState.routeDistanceKm = targetKm;
        appState.routeTimeMin = appState.activity == 'Walk'
            ? appState.distance * 12
            : appState.distance * 7;
      }

      // Switch to the Route tab
      widget.onRouteGenerated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate route. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingRoute = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App title
            const Text(
              'FitRoute',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),

            // Tappable location row — tap to get GPS location
            GestureDetector(
              onTap: _getLocation,
              child: Row(
                children: [
                  const Icon(
                    Icons.navigation_outlined,
                    size: 14,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    appState.locationName,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Activity selector
            const Text(
              'Activity',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActivityButton(
                    label: '🚶 Walk',
                    selected: appState.activity == 'Walk',
                    color: const Color(0xFF3B82F6),
                    onTap: () => setState(() => appState.activity = 'Walk'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActivityButton(
                    label: '🏃 Jog',
                    selected: appState.activity == 'Jog',
                    color: const Color(0xFF10B981),
                    onTap: () => setState(() => appState.activity = 'Jog'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Distance selector
            const Text(
              'Distance',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 12),
            _DistanceCard(
              distances: _distances,
              selected: appState.distance,
              onChanged: (d) => setState(() => appState.distance = d),
            ),
            const SizedBox(height: 28),

            // Generate Route button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _generatingRoute ? null : _generateRoute,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF93C5FD),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 4,
                  shadowColor: const Color(0xFF3B82F6).withOpacity(0.4),
                ),
                child: _generatingRoute
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Generating...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        'Generate Route',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            const Center(
              child: Text(
                'Routes generated based on your location',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Activity Button ──────────────────────────────────────────────────────────
// Animated button that highlights in blue (Walk) or green (Jog) when selected.

class _ActivityButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ActivityButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : Colors.grey.shade200),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Distance Card ────────────────────────────────────────────────────────────
// Shows distance options as selectable circles and the current value large.

class _DistanceCard extends StatelessWidget {
  final List<int> distances;
  final int selected;
  final Function(int) onChanged;

  const _DistanceCard({
    required this.distances,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Row of distance circle buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: distances.map((d) {
              final isSelected = d == selected;
              return GestureDetector(
                onTap: () => onChanged(d),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFF2F4F8),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '$d',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const Divider(height: 28),
          // Large display of selected distance
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$selected',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 38,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const TextSpan(
                  text: ' km',
                  style: TextStyle(color: Colors.grey, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Route Screen ─────────────────────────────────────────────────────────────
// Displays the generated route on a flutter_map (OpenStreetMap) with stats.

class RouteScreen extends StatefulWidget {
  final VoidCallback onGenerateAnother;
  const RouteScreen({super.key, required this.onGenerateAnother});

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  final MapController _mapController = MapController();
  bool _isTracking = false; // Toggles Start/Pause button state

  void _startRoute() {
    if (appState.routePoints == null) return;
    setState(() => _isTracking = !_isTracking);
    if (_isTracking) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🏁 Route started! Follow the blue line.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = appState.routePoints;
    final dist = appState.routeDistanceKm;
    final time = appState.routeTimeMin;

    // Show placeholder if no route has been generated yet
    if (points == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.route, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No route yet',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Go to Home and generate a route',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── Map (takes remaining screen space) ────────────────────────────
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: points[0], initialZoom: 15),
            children: [
              // OpenStreetMap tile layer
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.fitroute',
              ),
              // Blue polyline drawn along the route points
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: points,
                    strokeWidth: 5,
                    color: const Color(0xFF3B82F6),
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ],
              ),
              // Start (green) and end (red) markers
              MarkerLayer(
                markers: [
                  Marker(
                    point: points.first,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF10B981),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Marker(
                    point: points.last,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFEF4444),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Bottom panel with stats and buttons ───────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            children: [
              // Stats row: distance / time / calories
              Row(
                children: [
                  Expanded(
                    child: _InfoCard(
                      icon: Icons.location_on_outlined,
                      label: 'Distance',
                      value: dist != null
                          ? '${dist.toStringAsFixed(1)} km'
                          : '— km',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InfoCard(
                      icon: Icons.timer_outlined,
                      label: 'Est. Time',
                      value: time != null ? '$time min' : '— min',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InfoCard(
                      icon: Icons.local_fire_department_outlined,
                      label: 'Calories',
                      // Walk burns ~60 kcal/km, jog burns ~80 kcal/km
                      value: dist != null
                          ? '${(dist * (appState.activity == 'Walk' ? 60 : 80)).round()} kcal'
                          : '—',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Generate another route button
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: widget.onGenerateAnother,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Generate Another Route'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Start / Pause route button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _startRoute,
                  icon: Icon(
                    _isTracking ? Icons.pause : Icons.play_arrow,
                    size: 22,
                  ),
                  label: Text(_isTracking ? 'Pause Route' : 'Start Route'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 4,
                    shadowColor: const Color(0xFF10B981).withOpacity(0.4),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Small stat card used in the Route screen bottom panel
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey, size: 16),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─── Info / Weather Screen ────────────────────────────────────────────────────
// appState.notify() via addListener so it rebuilds the moment weather data
// comes back from the Open-Meteo API call triggered on the Home screen.

class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});

  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  @override
  void initState() {
    super.initState();
    // Subscribe to global state changes — rebuilds this screen when
    // appState.notify() is called (e.g. when weather or location updates)
    appState.addListener(_onAppStateChanged);
  }

  @override
  void dispose() {
    // Always unsubscribe when the widget is removed to avoid memory leaks
    appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  // Triggers a rebuild of this screen
  void _onAppStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final w = appState.weather;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weather & Conditions',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              appState.locationName,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 22),

            // Show placeholder until weather data has loaded
            if (w == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text(
                    '📍 Get your location on the\nHome tab to see weather',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
              )
            else
              // Weather card with temp, emoji, wind, humidity
              _WeatherCard(weather: w, locationName: appState.locationName),

            const SizedBox(height: 18),

            // Good/bad conditions advice card
            if (w != null)
              _ConditionCard(weather: w, activity: appState.activity),

            const SizedBox(height: 16),

            // Morning / Afternoon / Evening forecast rows
            if (w != null && w.forecast.isNotEmpty)
              _ForecastCard(forecast: w.forecast),
          ],
        ),
      ),
    );
  }
}

// ─── Weather Card ─────────────────────────────────────────────────────────────
// Blue gradient card showing temperature, emoji, wind, humidity, conditions.

class _WeatherCard extends StatelessWidget {
  final WeatherData weather;
  final String locationName;

  const _WeatherCard({required this.weather, required this.locationName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${weather.tempF.round()}°F',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.w200,
                ),
              ),
              Text(weather.emoji, style: const TextStyle(fontSize: 48)),
            ],
          ),
          Text(
            '$locationName · ${weather.tempC.round()}°C',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 18),
          const Divider(color: Colors.white24),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _WeatherMini(
                icon: Icons.air,
                label: 'Wind',
                value: '${weather.windMph} mph',
              ),
              _WeatherMini(
                icon: Icons.water_drop_outlined,
                label: 'Humidity',
                value: '${weather.humidity}%',
              ),
              _WeatherMini(
                icon: Icons.wb_cloudy_outlined,
                label: 'Conditions',
                value: weather.label.split(' ')[0],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Small column widget used inside the weather card
class _WeatherMini extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WeatherMini({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Condition Card ───────────────────────────────────────────────────────────
// Green card for good conditions, yellow card for poor conditions.

class _ConditionCard extends StatelessWidget {
  final WeatherData weather;
  final String activity;

  const _ConditionCard({required this.weather, required this.activity});

  @override
  Widget build(BuildContext context) {
    final good = weather.isGoodForActivity;
    final bg = good ? const Color(0xFFDFF7EF) : const Color(0xFFFEF3C7);
    final iconBg = good ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    final textColor = good ? const Color(0xFF065f46) : const Color(0xFF92400e);
    final title = good
        ? 'Great conditions for outdoor activity'
        : 'Moderate conditions';

    // Pick a message based on what the weather is actually like
    String body;
    if (good) {
      body =
          '${weather.label} and comfortable temperature — perfect for a ${activity.toLowerCase()}!';
    } else if (weather.code > 48) {
      body = 'Wet or stormy conditions. Consider waiting for better weather.';
    } else if (weather.tempC < 5) {
      body = 'Cold conditions. Dress warmly before heading out!';
    } else if (weather.tempC > 35) {
      body = 'Very hot outside. Stay hydrated and go early morning.';
    } else {
      body = '${weather.label} conditions. Check your gear before heading out.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: iconBg,
            child: Icon(
              good ? Icons.directions_run : Icons.warning_outlined,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(color: textColor, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Forecast Card ────────────────────────────────────────────────────────────
// Shows morning / afternoon / evening temperature rows.

class _ForecastCard extends StatelessWidget {
  final List<HourlyForecast> forecast;

  const _ForecastCard({required this.forecast});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's Forecast",
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 14),
          ...forecast.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Text(f.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(f.label, style: const TextStyle(fontSize: 13)),
                  ),
                  Text(
                    '${f.tempF.round()}°F',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
}

// ─── Weather Service ──────────────────────────────────────────────────────────
// Calls the Open-Meteo API (free, no key needed) to get current weather
// and an hourly forecast for the user's location.

class WeatherService {
  static Future<WeatherData?> fetch(double lat, double lng) async {
    try {
      // Build the Open-Meteo API request URL
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lng'
        '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code'
        '&hourly=temperature_2m,weather_code'
        '&timezone=auto'
        '&forecast_days=1',
      );
      final r = await http.get(url);
      if (r.statusCode != 200) return null;

      final d = json.decode(r.body);
      final c = d['current']; // Current conditions
      final hourly = d['hourly']; // Hourly forecast array

      // Extract hourly arrays to build the 3-slot forecast
      final times = List<String>.from(hourly['time']);
      final hourlyTemps = List<double>.from(
        hourly['temperature_2m'].map((v) => v.toDouble()),
      );
      final hourlyCodes = List<int>.from(
        hourly['weather_code'].map((v) => v as int),
      );

      // Pick out morning (8am), afternoon (2pm), evening (7pm) slots
      List<HourlyForecast> forecast = [];
      for (final slot in [
        {'label': 'Morning', 'hour': 8},
        {'label': 'Afternoon', 'hour': 14},
        {'label': 'Evening', 'hour': 19},
      ]) {
        final idx = times.indexWhere(
          (t) => DateTime.parse(t).hour == slot['hour'],
        );
        if (idx >= 0) {
          final tempF = hourlyTemps[idx] * 9 / 5 + 32;
          final code = hourlyCodes[idx];
          String emoji;
          if (code == 0)
            emoji = '☀️';
          else if (code <= 3)
            emoji = '⛅';
          else if (code <= 48)
            emoji = '🌫️';
          else if (code <= 67)
            emoji = '🌧️';
          else
            emoji = '⛈️';
          forecast.add(
            HourlyForecast(
              label: slot['label'] as String,
              tempF: tempF,
              emoji: emoji,
            ),
          );
        }
      }

      return WeatherData(
        tempC: (c['temperature_2m'] as num).toDouble(),
        humidity: (c['relative_humidity_2m'] as num).toInt(),
        windKph: (c['wind_speed_10m'] as num).toDouble(),
        code: (c['weather_code'] as num).toInt(),
        forecast: forecast,
      );
    } catch (_) {
      return null; // Silently fail — UI handles null weather
    }
  }
}

// ─── Route Generator ──────────────────────────────────────────────────────────
// Step 1 — generate(): Creates waypoints in a circular loop.
//   Uses the circumference formula: radius = targetKm / (2π)
//   so that walking the full loop equals the selected distance.
//
// Step 2 — snapToRoads(): Sends waypoints to the OSRM routing API
//   which returns a route snapped to real walkable streets.
//   If OSRM returns a distance more than 2.5× the target (the old 16km bug),
//   the result is rejected and the raw generated points are used instead.

class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  RouteResult({required this.points, required this.distanceKm});
}

class RouteGenerator {
  static const double _earthR = 6371.0; // Earth radius in km

  /// Generates a roughly circular loop with perimeter ≈ targetKm.
  static List<LatLng> generate(double lat, double lng, double targetKm) {
    final rng = Random();

    // radius = targetKm / (2π)  so circumference = 2π × radius = targetKm
    final radiusKm = targetKm / (2 * pi);
    final radiusDeg = radiusKm / _earthR * (180 / pi);

    // More waypoints for longer distances = smoother loop on the map
    final numPoints = max(6, min(12, (targetKm * 2).round()));

    // Random start angle so each generated route looks different
    final angleOffset = rng.nextDouble() * 2 * pi;

    final points = <LatLng>[];
    for (int i = 0; i < numPoints; i++) {
      final angle = angleOffset + (i / numPoints) * 2 * pi;
      // Add ±10% jitter so it isn't a perfect circle
      final jitter = 1.0 + (rng.nextDouble() - 0.5) * 0.2;
      final r = radiusDeg * jitter;
      final newLat = lat + r * sin(angle);
      final newLng = lng + r * cos(angle) / cos(lat * pi / 180);
      points.add(LatLng(newLat, newLng));
    }

    // Close the loop by returning to the first point
    points.add(points.first);
    return points;
  }

  /// Snaps the generated waypoints to real roads using the OSRM API.
  /// Returns null if the API fails OR if the result is too far off target.
  static Future<RouteResult?> snapToRoads(
    List<LatLng> points,
    double targetKm,
  ) async {
    try {
      // Format waypoints as "lng,lat;lng,lat;..." for OSRM
      final coordStr = points
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/foot/$coordStr'
        '?overview=full&geometries=geojson&steps=false',
      );
      final r = await http.get(url).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;

      final d = json.decode(r.body);
      if (d['code'] != 'Ok') return null;

      final route = d['routes'][0];
      final coords = route['geometry']['coordinates'] as List;

      // Convert [lng, lat] pairs from GeoJSON to LatLng objects
      final snapped = coords
          .map<LatLng>((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
          .toList();

      final distanceKm = (route['distance'] as num).toDouble() / 1000;

      // FIX: Reject result if OSRM returned something wildly over target.
      // This prevents the bug where selecting 1km gave a 16km route because
      // OSRM was routing between waypoints in a way that inflated the path.
      if (distanceKm > targetKm * 2.5) return null;

      return RouteResult(points: snapped, distanceKm: distanceKm);
    } catch (_) {
      return null; // Timeout or network error — caller uses fallback
    }
  }
}
