import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _selectedIndex = 0;

  void _onTabTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  final List<Widget> _screens = [
    SensorDataScreen(),
    MapScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text("Sensor & Map App")),
        body: _screens[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onTabTapped,
          items: [
            BottomNavigationBarItem(
                icon: Icon(Icons.data_usage), label: "Data"),
            BottomNavigationBarItem(icon: Icon(Icons.map), label: "Maps"),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── SensorDataScreen ─────────────────────────

class SensorDataScreen extends StatefulWidget {
  const SensorDataScreen({super.key});

  @override
  _SensorDataScreenState createState() => _SensorDataScreenState();
}

class _SensorDataScreenState extends State<SensorDataScreen> {
  AccelerometerEvent? accelerometerData;
  GyroscopeEvent? gyroscopeData;
  Position? locationData;
  double? locationAccuracy;
  Timer? sensorTimer;
  bool isReading = false;
  String? sessionId;
  String? deviceId;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _getDeviceId();
  }

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("Location services are disabled.");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print("Location permission denied.");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print("Location permission permanently denied.");
      return;
    }
  }

  Future<void> _getDeviceId() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    setState(() {
      deviceId = androidInfo.id;
    });
  }

  void startSensorReadings() {
    if (!isReading) {
      setState(() {
        isReading = true;
        sessionId = Uuid().v4();
      });

      accelerometerEvents.listen((event) {
        setState(() => accelerometerData = event);
      });

      gyroscopeEvents.listen((event) {
        setState(() => gyroscopeData = event);
      });

      sensorTimer = Timer.periodic(Duration(milliseconds: 200), (timer) async {
        try {
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation,
          );
          setState(() {
            locationData = position;
            locationAccuracy = position.accuracy;
          });
          sendDataToServer();
        } catch (e) {
          print("Error fetching location: $e");
        }
      });
    }
  }

  void stopSensorReadings() {
    sensorTimer?.cancel();
    setState(() => isReading = false);
  }

  Future<void> sendDataToServer() async {
    if (locationData == null || sessionId == null || deviceId == null) return;

    Map<String, dynamic> data = {
      "session_id": sessionId,
      "device_id": deviceId,
      "timestamp": DateTime.now().toIso8601String(),
      "accelerometer": {
        "x": accelerometerData?.x ?? 0.0,
        "y": accelerometerData?.y ?? 0.0,
        "z": accelerometerData?.z ?? 0.0,
      },
      "gyroscope": {
        "x": gyroscopeData?.x ?? 0.0,
        "y": gyroscopeData?.y ?? 0.0,
        "z": gyroscopeData?.z ?? 0.0,
      },
      "location": {
        "latitude": locationData?.latitude,
        "longitude": locationData?.longitude,
        "accuracy": locationAccuracy,
      },
    };

    try {
      final response = await http.post(
        Uri.parse("http://denis.networkgeek.in:80/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      );
      if (response.statusCode != 200) {
        print("Failed to send data");
      }
    } catch (e) {
      print("Error sending data to server: $e");
    }
  }

  String formatSensorData(dynamic data) {
    return data != null
        ? "x: ${data.x.toStringAsFixed(2)} y: ${data.y.toStringAsFixed(2)} z: ${data.z.toStringAsFixed(2)}"
        : "Fetching...";
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Session ID: $sessionId"),
            Text("Device ID: $deviceId"),
            Text("Accelerometer:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            Text(formatSensorData(accelerometerData)),
            SizedBox(height: 10),
            Text("Gyroscope:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            Text(formatSensorData(gyroscopeData)),
            SizedBox(height: 10),
            Text("Location:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            Text(
              locationData != null
                  ? "${locationData!.latitude}, ${locationData!.longitude} (Accuracy: ${locationAccuracy?.toStringAsFixed(2)} m)"
                  : "Fetching location...",
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: startSensorReadings,
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: Text("Start"),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: stopSensorReadings,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Text("Stop"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── MapScreen ─────────────────────────

class LocationSuggestion {
  final String name;
  final LatLng coordinates;

  LocationSuggestion(this.name, this.coordinates);
}

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LocationSuggestion? startLocation;
  LocationSuggestion? endLocation;
  List<LatLng> routePoints = [];
  String? eta;
  String? distance;
  List<LatLng> speedBreakerLocations = [];

  @override
  void initState() {
    super.initState();
    loadLocations();
  }

  Future<void> loadLocations() async {
    speedBreakerLocations = await fetchSpeedBreakerLocations();
    setState(() {}); 
  }

Future<List<LatLng>> fetchSpeedBreakerLocations() async {
  final response = await http.get(Uri.parse('https://denis.networkgeek.in/'));

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final locations = data['locations'] as List;

    return locations.map((location) {
      return LatLng(location['latitude'], location['longitude']);
    }).toList();
  } else {
    throw Exception('Failed to load speed breaker locations');
  }
}

  Future<List<LocationSuggestion>> fetchSuggestions(String query) async {
    final url = Uri.parse('https://photon.komoot.io/api/?q=$query&limit=5');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final features = data['features'] as List;

      return features.map((feature) {
        final name = feature['properties']['name'] ?? 'Unknown';
        final coords = feature['geometry']['coordinates'];
        return LocationSuggestion(name, LatLng(coords[1], coords[0]));
      }).toList();
    } else {
      return [];
    }
  }

  Future<void> fetchRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
      'http://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
      '?overview=full&geometries=geojson',
    );
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final route = data['routes'][0];

      final coordinates = route['geometry']['coordinates'] as List;
      final points =
          coordinates.map((point) => LatLng(point[1], point[0])).toList();

      final durationInSeconds = route['duration'] as double;
      final distanceInMeters = route['distance'] as double;

      setState(() {
        routePoints = points;
        eta = formatDuration(Duration(seconds: durationInSeconds.round()));
        distance = (distanceInMeters / 1000).toStringAsFixed(2) + " km";
      });

      if (points.isNotEmpty) {
        double avgLat = points.map((p) => p.latitude).reduce((a, b) => a + b) /
            points.length;
        double avgLng = points.map((p) => p.longitude).reduce((a, b) => a + b) /
            points.length;
        _mapController.move(LatLng(avgLat, avgLng), 14.0);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to fetch route')),
      );
    }
  }

  String formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours} hr ${duration.inMinutes % 60} min';
    } else {
      return '${duration.inMinutes} min';
    }
  }

  Widget buildSearchField(
      String label, Function(LocationSuggestion) onSelected) {
    return TypeAheadField<LocationSuggestion>(
      suggestionsCallback: fetchSuggestions,
      itemBuilder: (context, suggestion) =>
          ListTile(title: Text(suggestion.name)),
      onSelected: onSelected,
      builder: (context, controller, focusNode) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
          ),
        );
      },
    );
  }

  List<Marker> buildMarkers() {
    final markers = <Marker>[
      ...speedBreakerLocations.map((location) => Marker(
            point: location,
            width: 40,
            height: 40,
            child: const Icon(Icons.warning, color: Colors.orange, size: 30),
          )),
    ];

    if (startLocation != null) {
      markers.add(Marker(
        point: startLocation!.coordinates,
        width: 40,
        height: 40,
        child: const Icon(Icons.location_on, color: Colors.green, size: 35),
      ));
    }

    if (endLocation != null) {
      markers.add(Marker(
        point: endLocation!.coordinates,
        width: 40,
        height: 40,
        child: const Icon(Icons.flag, color: Colors.red, size: 35),
      ));
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "RoadSense",
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                margin: const EdgeInsets.all(7.0),
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: buildSearchField('Start Location', (suggestion) {
                        setState(() => startLocation = suggestion);
                      }),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: buildSearchField('Destination', (suggestion) {
                        setState(() => endLocation = suggestion);
                      }),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 12.0),
                      child: ElevatedButton(
                        onPressed:
                            (startLocation != null && endLocation != null)
                                ? () => fetchRoute(startLocation!.coordinates,
                                    endLocation!.coordinates)
                                : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 12.0, horizontal: 20.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 4,
                        ),
                        child: const Text('Get Route'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: speedBreakerLocations.first,
                    initialZoom: 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                    ),
                    MarkerLayer(markers: buildMarkers()),
                    if (routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: routePoints,
                            strokeWidth: 7.0,
                            color: Colors.blueAccent,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (eta != null && distance != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(12.0),
                padding: const EdgeInsets.symmetric(
                    vertical: 14.0, horizontal: 20.0),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          endLocation?.name ?? 'Destination',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('ETA: $eta • Distance: $distance'),
                      ],
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
