import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import '../../../../core/accessibility/a11y_tap.dart';
import '../../../../core/accessibility/ui_speech.dart';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';
import '../../data/datasources/location_service.dart';
import '../../data/datasources/map_api_client.dart';
import '../../domain/guidance.dart';

/// Mapa con GPS real, búsqueda (Nominatim) y guía a pie por voz (OSRM).
class MapaScreen extends StatefulWidget {
  /// Inyectables para pruebas; por defecto usan la red y el GPS reales.
  final MapApiClient? apiClient;
  final LocationService locationService;

  const MapaScreen({
    super.key,
    this.apiClient,
    this.locationService = const LocationService(),
  });

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _Category {
  final String label;
  final String query;
  final IconData icon;
  const _Category(this.label, this.query, this.icon);
}

const _categories = [
  _Category('Farmacias', 'farmacia', Icons.local_pharmacy_rounded),
  _Category('Paraderos', 'parada de autobús', Icons.directions_bus_rounded),
  _Category('Mercados', 'mercado', Icons.shopping_basket_rounded),
  _Category('Hospitales', 'hospital', Icons.local_hospital_rounded),
];

// Patrones de vibración: izquierda = 2 pulsos cortos, derecha = 3 pulsos.
const _vibLeft = [0, 120, 110, 120];
const _vibRight = [0, 120, 110, 120, 110, 120];
const _vibArrival = [0, 500];

/// Centro provisional mientras llega el primer dato del GPS (Lima).
final _fallbackCenter = LatLng(-12.0464, -77.0428);

class _MapaScreenState extends State<MapaScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  late final MapApiClient _api = widget.apiClient ?? MapApiClient();

  bool _mapReady = false;
  bool _useDarkMap = true;
  bool _follow = true;

  // --- Ubicación ---
  bool _locationStarted = false;
  LocationAccess? _access;
  StreamSubscription<Position>? _posSub;
  LatLng? _position;
  double? _accuracy;
  bool _hadFix = false;

  // --- Búsqueda ---
  bool _isSearchFocused = false;
  bool _searching = false;
  String _resultsTitle = 'Resultados';
  String? _searchMessage;
  List<Place> _results = [];
  Timer? _debounce;
  int _searchSeq = 0;

  // --- Ruta y guía ---
  Place? _destination;
  WalkingRoute? _route;
  GuidanceEngine? _engine;
  GuidanceSnapshot? _snap;
  bool _loadingRoute = false;
  bool _rerouting = false;
  DateTime? _rerouteFailedAt;
  bool _locating = false;
  String? _statusMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // La pantalla vive en un IndexedStack: pedimos el GPS solo cuando la
    // pestaña de mapa se muestra (TickerMode se desactiva si está oculta).
    if (!_locationStarted && TickerMode.valuesOf(context).enabled) {
      _locationStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    if (widget.apiClient == null) _api.close();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Voz y vibración
  // -------------------------------------------------------------------------

  /// Guía de navegación: siempre por el TTS de la app (es información
  /// crítica, aunque haya lector de pantalla activo).
  void _say(String text) {
    if (!mounted || text.isEmpty) return;
    context.read<AppState>().speak(text);
  }

  Future<void> _vibrate(List<int> pattern) async {
    if (!mounted || !context.read<AppState>().vibrationEnabled) return;
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: pattern);
      }
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Ubicación
  // -------------------------------------------------------------------------

  Future<void> _initLocation({bool fromUser = false}) async {
    final access = await widget.locationService.ensurePermission();
    if (!mounted) return;
    setState(() => _access = access);
    if (access != LocationAccess.granted) {
      final msg = LocationService.messageFor(access);
      setState(() => _statusMessage = msg);
      _say(msg);
      if (fromUser) await widget.locationService.openSettings(access);
      return;
    }
    setState(() => _statusMessage = 'Buscando señal GPS…');
    final last = await widget.locationService.lastKnown();
    if (last != null && mounted && _position == null) _onPosition(last);
    await _posSub?.cancel();
    _posSub = widget.locationService.positions().listen(
      _onPosition,
      onError: (Object e) {
        if (!mounted) return;
        const msg = 'Se perdió la señal GPS. Revisa que la ubicación esté activa.';
        setState(() => _statusMessage = msg);
        _say(msg);
      },
    );
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    final ll = LatLng(p.latitude, p.longitude);
    final firstFix = !_hadFix;
    setState(() {
      _position = ll;
      _accuracy = p.accuracy;
      _hadFix = true;
      if (_statusMessage == 'Buscando señal GPS…') _statusMessage = null;
    });
    if (_mapReady && (_follow || firstFix)) {
      _mapController.move(ll, firstFix ? 17 : _mapController.camera.zoom);
    }

    final engine = _engine;
    if (engine == null || engine.arrived || _rerouting) return;
    if (engine.lastSnapshot?.needsReroute == true) {
      // Re-ruta pendiente tras un fallo de red: reintentar cada 15 s.
      final failed = _rerouteFailedAt;
      if (failed == null ||
          DateTime.now().difference(failed) > const Duration(seconds: 15)) {
        _reroute();
      }
      return;
    }
    final snap = engine.update(ll, accuracy: p.accuracy);
    setState(() => _snap = snap);
    _handleEvents(snap.events);
    if (snap.needsReroute) _reroute();
  }

  void _handleEvents(List<GuidanceEvent> events, {String prefix = ''}) {
    final text = [
      if (prefix.isNotEmpty) prefix,
      ...events.map((e) => e.message),
    ].join(' ');
    _say(text);
    for (final e in events) {
      if (e.type == GuidanceEventType.turn) {
        if (e.haptic == TurnSide.left) _vibrate(_vibLeft);
        if (e.haptic == TurnSide.right) _vibrate(_vibRight);
      } else if (e.type == GuidanceEventType.arrived) {
        _vibrate(_vibArrival);
      }
    }
  }

  void _recenterUser() {
    final pos = _position;
    if (pos == null) {
      _say(_noFixMessage());
      return;
    }
    setState(() => _follow = true);
    if (_mapReady) _mapController.move(pos, 17.0);
    speakUi(context, 'Centrando mapa en tu ubicación.');
  }

  String _noFixMessage() {
    final access = _access;
    if (access != null && access != LocationAccess.granted) {
      return LocationService.messageFor(access);
    }
    return 'Aún no tengo tu ubicación. Espera la señal del GPS, mejor al aire libre.';
  }

  // -------------------------------------------------------------------------
  // ¿Dónde estoy?
  // -------------------------------------------------------------------------

  Future<void> _whereAmI() async {
    final pos = _position;
    if (pos == null) {
      _say(_noFixMessage());
      return;
    }
    if (_locating) return;
    setState(() => _locating = true);
    _say('Buscando tu dirección.');
    try {
      final text = await _api.reverse(pos);
      if (!mounted) return;
      setState(() => _statusMessage = text);
      _say(text);
    } on MapApiException catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = e.message);
      _say(e.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // -------------------------------------------------------------------------
  // Búsqueda
  // -------------------------------------------------------------------------

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    setState(() {});
    final q = query.trim();
    if (q.length < 3) {
      setState(() {
        _results = [];
        _searchMessage = q.isEmpty ? null : 'Escribe al menos 3 letras.';
      });
      return;
    }
    // Debounce: Nominatim permite como máximo 1 petición por segundo.
    _debounce = Timer(
      const Duration(milliseconds: 900),
      () => _runSearch(q, title: 'Resultados para "$q"'),
    );
  }

  Future<void> _runSearch(
    String query, {
    required String title,
    bool bounded = false,
    bool announce = false,
  }) async {
    final seq = ++_searchSeq;
    setState(() {
      _isSearchFocused = true;
      _searching = true;
      _searchMessage = null;
      _resultsTitle = title;
    });
    try {
      final results = await _api.searchPlaces(
        query,
        near: _position,
        bounded: bounded && _position != null,
        radiusKm: bounded ? 3 : 15,
      );
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = results;
        _searchMessage = results.isEmpty ? 'No encontré lugares.' : null;
      });
      if (announce) {
        if (results.isEmpty) {
          _say('No encontré $title.');
        } else {
          final first = results.first;
          final dist = first.distanceMeters != null
              ? ', a ${formatDistance(first.distanceMeters!)}'
              : '';
          _say(
            'Encontré ${results.length} lugares. El más cercano es '
            '${first.name}$dist. Toca un resultado para ir.',
          );
        }
      }
    } on MapApiException catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = [];
        _searchMessage = e.message;
      });
      _say(e.message);
    } finally {
      if (mounted && seq == _searchSeq) setState(() => _searching = false);
    }
  }

  void _searchCategory(_Category cat) {
    if (_position == null) {
      _say(_noFixMessage());
      return;
    }
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    _say('Buscando ${cat.label.toLowerCase()} cercanas.');
    _runSearch(
      cat.query,
      title: '${cat.label} cerca de ti',
      bounded: true,
      announce: true,
    );
  }

  void _closeSearch() {
    setState(() => _isSearchFocused = false);
    FocusScope.of(context).unfocus();
  }

  // -------------------------------------------------------------------------
  // Ruta
  // -------------------------------------------------------------------------

  Future<void> _startRoute(Place place) async {
    final pos = _position;
    FocusScope.of(context).unfocus();
    if (pos == null) {
      _say(_noFixMessage());
      return;
    }
    setState(() {
      _isSearchFocused = false;
      _searchController.text = place.name;
      _destination = place;
      _loadingRoute = true;
      _route = null;
      _engine = null;
      _snap = null;
      _statusMessage = null;
    });
    _say('Calculando ruta a pie hasta ${place.name}.');
    try {
      final route = await _api.walkingRoute(pos, place.location);
      if (!mounted || _destination != place) return;
      final engine = GuidanceEngine(route);
      final start = engine.start(destinationName: place.name);
      final snap = engine.update(_position ?? pos, accuracy: _accuracy);
      setState(() {
        _route = route;
        _engine = engine;
        _snap = snap;
        _follow = true;
      });
      if (_mapReady && route.geometry.length > 1) {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: route.geometry,
            padding: const EdgeInsets.fromLTRB(40, 170, 80, 330),
            maxZoom: 18,
          ),
        );
      }
      _handleEvents(snap.events, prefix: start.message);
      if (snap.needsReroute) _reroute();
    } on MapApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _destination = null;
        _statusMessage = e.message;
      });
      _say(e.message);
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  Future<void> _reroute() async {
    final dest = _destination;
    final pos = _position;
    if (_rerouting || dest == null || pos == null) return;
    setState(() => _rerouting = true);
    try {
      final route = await _api.walkingRoute(pos, dest.location);
      if (!mounted || _destination != dest) return;
      final engine = GuidanceEngine(route);
      final start = engine.start(reroute: true);
      final snap = engine.update(_position ?? pos, accuracy: _accuracy);
      setState(() {
        _route = route;
        _engine = engine;
        _snap = snap;
        _rerouteFailedAt = null;
      });
      _handleEvents(snap.events, prefix: start.message);
    } on MapApiException catch (e) {
      _rerouteFailedAt = DateTime.now();
      _say('No pude recalcular la ruta. ${e.message}');
    } finally {
      if (mounted) setState(() => _rerouting = false);
    }
  }

  void _repeatInstruction() {
    final engine = _engine;
    if (engine == null) return;
    if (_rerouting) {
      _say('Recalculando ruta.');
      return;
    }
    _say(engine.repeatText());
  }

  void _endRoute() {
    setState(() {
      _destination = null;
      _route = null;
      _engine = null;
      _snap = null;
      _rerouting = false;
      _searchController.clear();
      _results = [];
    });
    _say('Ruta terminada.');
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final navigating = _destination != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildMapCanvas(),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSearchBar(),
                  if (!_isSearchFocused) _buildCategoryChips(),
                ],
              ),
            ),
          ),

          if (_isSearchFocused)
            Positioned(
              top: topInset + 76,
              left: 14,
              right: 14,
              bottom: 100,
              child: _buildResultsPanel(),
            ),

          if (!_isSearchFocused)
            Positioned(
              right: 14,
              top: topInset + 136,
              child: _buildMapControls(),
            ),

          if (!_isSearchFocused)
            Positioned(
              left: 12,
              right: 12,
              bottom: 84, // Por encima de la barra de navegación principal
              child: _glassCard(
                borderColor: navigating
                    ? _sideColor(_snap?.nextStep)
                    : RiqsiTheme.accentCyan.withValues(alpha: 0.5),
                child: navigating ? _buildNavigationCard() : _buildIdleCard(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapCanvas() {
    final String label;
    if (_position == null) {
      label = 'Mapa. ${_statusMessage ?? 'Esperando tu ubicación GPS.'}';
    } else if (_destination != null) {
      label =
          'Mapa con tu ubicación y la ruta a pie hasta ${_destination!.name}. '
          'La indicación actual está en la tarjeta inferior.';
    } else {
      label = 'Mapa centrado en tu ubicación. Usa el buscador para elegir un destino.';
    }
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(child: _buildFlutterMap()),
    );
  }

  Widget _buildFlutterMap() {
    final pos = _position;
    final dest = _destination;
    final route = _route;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: pos ?? _fallbackCenter,
        initialZoom: pos == null ? 13 : 17,
        minZoom: 3,
        maxZoom: 19,
        onMapReady: () {
          _mapReady = true;
          final p = _position;
          if (p != null) _mapController.move(p, 17);
        },
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && _follow) setState(() => _follow = false);
        },
        onTap: (_, _) {
          if (_isSearchFocused) _closeSearch();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.riqsi',
          maxZoom: 19,
          tileBuilder: _useDarkMap ? darkModeTileBuilder : null,
        ),
        if (route != null && route.geometry.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route.geometry,
                color: RiqsiTheme.accentCyan,
                strokeWidth: 6.0,
                borderColor: Colors.black54,
                borderStrokeWidth: 2.0,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (pos != null)
              Marker(
                point: pos,
                width: 50,
                height: 50,
                child: _buildUserLocationMarker(),
              ),
            if (dest != null)
              Marker(
                point: dest.location,
                width: 44,
                height: 44,
                child: _buildDestinationMarker(),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildUserLocationMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: RiqsiTheme.accentCyan.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
        Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(
            color: Color(0xFF00B0FF),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  Widget _buildDestinationMarker() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFFF2A2A),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
      ),
      child: const Icon(Icons.flag_rounded, size: 20, color: Colors.white),
    );
  }

  Widget _buildSearchBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E2430).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: RiqsiTheme.accentCyan.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              const ExcludeSemantics(
                child: Icon(
                  Icons.search_rounded,
                  color: RiqsiTheme.accentCyan,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textInputAction: TextInputAction.search,
                  onTap: () => setState(() => _isSearchFocused = true),
                  onChanged: _onSearchChanged,
                  onSubmitted: (q) {
                    _debounce?.cancel();
                    if (q.trim().isNotEmpty) {
                      _runSearch(
                        q.trim(),
                        title: 'Resultados para "${q.trim()}"',
                        announce: true,
                      );
                    }
                  },
                  decoration: const InputDecoration(
                    hintText: 'Buscar destino o dirección...',
                    hintStyle: TextStyle(color: Colors.white70, fontSize: 16),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (_searchController.text.isNotEmpty)
                A11yTap(
                  label: 'Borrar búsqueda',
                  onTap: () {
                    _debounce?.cancel();
                    _searchController.clear();
                    setState(() {
                      _results = [];
                      _searchMessage = null;
                    });
                  },
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          return A11yTap(
            label: 'Buscar ${cat.label.toLowerCase()} cercanas',
            hint: 'Muestra los lugares reales más cercanos a ti',
            onTap: () => _searchCategory(cat),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white54, width: 1),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4),
                ],
              ),
              child: Row(
                children: [
                  Icon(cat.icon, size: 16, color: RiqsiTheme.accentCyan),
                  const SizedBox(width: 6),
                  Text(
                    cat.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultsPanel() {
    Widget body;
    if (_searching) {
      body = Semantics(
        liveRegion: true,
        label: 'Buscando lugares',
        child: const Center(
          child: CircularProgressIndicator(color: RiqsiTheme.accentCyan),
        ),
      );
    } else if (_results.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _searchMessage ??
                'Escribe un destino o toca una categoría (Farmacias, Paraderos…).',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      );
    } else {
      body = ListView.separated(
        itemCount: _results.length,
        separatorBuilder: (_, _) =>
            const Divider(color: Colors.white10, height: 1),
        itemBuilder: (context, index) {
          final place = _results[index];
          final dist = place.distanceMeters != null
              ? formatDistance(place.distanceMeters!)
              : null;
          return Semantics(
            button: true,
            container: true,
            excludeSemantics: true,
            label:
                '${place.name}${place.address.isNotEmpty ? ', ${place.address}' : ''}'
                '${dist != null ? ', a $dist' : ''}',
            hint: 'Toca dos veces para iniciar la ruta a pie',
            onTap: () => _startRoute(place),
            child: ListTile(
              minVerticalPadding: 10,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: RiqsiTheme.accentCyan.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  color: RiqsiTheme.accentCyan,
                  size: 20,
                ),
              ),
              title: Text(
                place.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              subtitle: place.address.isEmpty
                  ? null
                  : Text(
                      place.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
              trailing: dist == null
                  ? null
                  : Text(
                      dist,
                      style: const TextStyle(
                        color: RiqsiTheme.accentCyan,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
              onTap: () => _startRoute(place),
            ),
          );
        },
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141923).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: RiqsiTheme.accentCyan.withValues(alpha: 0.4),
            ),
            boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 16)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          _resultsTitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    A11yTap(
                      label: 'Cerrar lista de lugares',
                      onTap: _closeSearch,
                      child: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(child: body),
              _attribution(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _circleButton(
          icon: _follow ? Icons.my_location_rounded : Icons.location_searching,
          tooltip: 'Centrar mapa en mi ubicación',
          color: RiqsiTheme.accentCyan,
          onTap: _recenterUser,
        ),
        const SizedBox(height: 8),
        _circleButton(
          icon: _useDarkMap ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          tooltip: _useDarkMap ? 'Cambiar a mapa claro' : 'Cambiar a mapa oscuro',
          color: Colors.white,
          onTap: () => setState(() => _useDarkMap = !_useDarkMap),
        ),
        const SizedBox(height: 8),
        _circleButton(
          icon: Icons.add_rounded,
          tooltip: 'Acercar mapa',
          color: Colors.white,
          onTap: () {
            if (!_mapReady) return;
            final cam = _mapController.camera;
            _mapController.move(cam.center, cam.zoom + 1);
          },
        ),
        const SizedBox(height: 8),
        _circleButton(
          icon: Icons.remove_rounded,
          tooltip: 'Alejar mapa',
          color: Colors.white,
          onTap: () {
            if (!_mapReady) return;
            final cam = _mapController.camera;
            _mapController.move(cam.center, cam.zoom - 1);
          },
        ),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return A11yTap(
      label: tooltip,
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF161B26).withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white54, width: 1.2),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _glassCard({required Widget child, required Color borderColor}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF121722).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: 0.25),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _attribution() {
    return const Padding(
      padding: EdgeInsets.only(top: 6, bottom: 2, left: 4),
      child: Text(
        '© OpenStreetMap · rutas OSRM',
        style: TextStyle(color: Colors.white54, fontSize: 11),
      ),
    );
  }

  /// Tarjeta sin ruta: estado del GPS + botón grande "¿Dónde estoy?".
  Widget _buildIdleCard() {
    final access = _access;
    final needsPermission = access != null && access != LocationAccess.granted;
    String status;
    if (_statusMessage != null) {
      status = _statusMessage!;
    } else if (_position == null) {
      status = 'Buscando señal GPS…';
    } else {
      final acc = _accuracy;
      status = acc != null
          ? 'GPS activo · precisión ${acc.round()} m'
          : 'GPS activo';
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          container: true,
          child: Text(
            status,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (needsPermission)
          _bigButton(
            label: 'Activar ubicación',
            icon: Icons.location_disabled_rounded,
            onTap: () => _initLocation(fromUser: true),
          )
        else
          _bigButton(
            label: _locating ? 'Buscando dirección…' : '¿Dónde estoy?',
            icon: Icons.person_pin_circle_rounded,
            onTap: _locating ? null : _whereAmI,
            hint: 'Dice por voz la calle y el distrito donde estás',
          ),
        _attribution(),
      ],
    );
  }

  /// Tarjeta de navegación: instrucción actual grande + distancia + acciones.
  Widget _buildNavigationCard() {
    final snap = _snap;
    final step = snap?.nextStep;
    final dest = _destination!;
    final color = _sideColor(step);

    String title;
    String detail;
    IconData icon;
    if (_loadingRoute) {
      title = 'Calculando ruta…';
      detail = 'Hacia ${dest.name}';
      icon = Icons.alt_route_rounded;
    } else if (_rerouting || (snap?.needsReroute ?? false)) {
      title = 'Recalculando ruta…';
      detail = 'Hacia ${dest.name}';
      icon = Icons.alt_route_rounded;
    } else if (snap == null || step == null) {
      title = 'Esperando GPS…';
      detail = 'Hacia ${dest.name}';
      icon = Icons.gps_not_fixed_rounded;
    } else if (snap.arrived) {
      title = 'Has llegado a tu destino';
      detail = dest.name;
      icon = Icons.check_circle_rounded;
    } else {
      title = step.isArrival ? 'Destino: ${dest.name}' : step.instruction;
      detail =
          'En ${formatDistance(snap.distanceToNext)} · '
          'faltan ${formatDistance(snap.distanceToDestination)}';
      icon = _stepIcon(step);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: '$title. $detail',
          child: ExcludeSemantics(
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(icon, color: color, size: 34),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _actionButton(
                label: 'Repetir',
                icon: Icons.volume_up_rounded,
                color: RiqsiTheme.accentCyan,
                onTap: _engine == null ? null : _repeatInstruction,
                semanticsLabel: 'Repetir indicación',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                label: '¿Dónde estoy?',
                icon: Icons.person_pin_circle_rounded,
                color: Colors.white,
                onTap: _locating ? null : _whereAmI,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                label: 'Terminar',
                icon: Icons.close_rounded,
                color: const Color(0xFFFF5252),
                onTap: _endRoute,
                semanticsLabel: 'Terminar ruta',
              ),
            ),
          ],
        ),
        _attribution(),
      ],
    );
  }

  Widget _bigButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    String? hint,
  }) {
    return A11yTap(
      label: label,
      hint: hint,
      onTap: onTap,
      showTooltip: false,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: RiqsiTheme.accentCyan,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.black, size: 28),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    String? semanticsLabel,
  }) {
    return A11yTap(
      label: semanticsLabel ?? label,
      onTap: onTap,
      showTooltip: false,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _sideColor(RouteStep? step) {
    if (step == null) return RiqsiTheme.accentCyan;
    if (_snap?.arrived ?? false) return const Color(0xFFFFD600);
    if (step.isArrival) return const Color(0xFFFFD600);
    switch (step.side) {
      case TurnSide.right:
        return const Color(0xFF00E676);
      case TurnSide.left:
        return const Color(0xFFB388FF);
      case TurnSide.none:
        return RiqsiTheme.accentCyan;
    }
  }

  IconData _stepIcon(RouteStep step) {
    if (step.isArrival) return Icons.flag_rounded;
    if (step.modifier == 'uturn') return Icons.u_turn_left_rounded;
    if (step.type.contains('roundabout') || step.type.contains('rotary')) {
      return Icons.roundabout_right_rounded;
    }
    final m = step.modifier ?? '';
    if (m == 'slight right') return Icons.turn_slight_right_rounded;
    if (m == 'slight left') return Icons.turn_slight_left_rounded;
    if (m.contains('right')) return Icons.turn_right_rounded;
    if (m.contains('left')) return Icons.turn_left_rounded;
    return Icons.straight_rounded;
  }
}
