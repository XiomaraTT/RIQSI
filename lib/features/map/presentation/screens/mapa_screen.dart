import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/riqsi_theme.dart';
import '../../../../state/app_state.dart';
import '../../data/datasources/navigation_api_datasource.dart';

class MapaScreen extends StatefulWidget {
  const MapaScreen({super.key});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final NavigationApiDataSource _apiDataSource = NavigationApiDataSource();

  // Ubicación inicial del usuario (ej. Lima Centro / Av. Arequipa)
  final LatLng _userLocation = LatLng(-12.046374, -77.042793);
  LatLng? _destinationLocation;
  List<LatLng> _routePolyline = [];

  bool _isSearchFocused = false;
  List<Map<String, dynamic>> _searchResults = [];
  bool _useDarkMap = true;
  bool _isPanelCollapsed = false;

  @override
  void initState() {
    super.initState();
    _searchResults = _apiDataSource.searchPlaces("");
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchResults = _apiDataSource.searchPlaces(query);
    });
  }

  void _selectDestination(Map<String, dynamic> place, AppState state) {
    final destLat = place["lat"] as double;
    final destLng = place["lng"] as double;
    final destName = place["name"] as String;

    final destPoint = LatLng(destLat, destLng);

    setState(() {
      _destinationLocation = destPoint;
      _searchController.text = destName;
      _isSearchFocused = false;

      // Generar puntos de la ruta peatonal
      _routePolyline = [
        _userLocation,
        LatLng(_userLocation.latitude - 0.0006, _userLocation.longitude),
        LatLng(_userLocation.latitude - 0.0006, destLng),
        destPoint,
      ];
    });

    FocusScope.of(context).unfocus();

    // Centrar mapa hacia el destino y la ruta
    _mapController.move(destPoint, 16.5);

    // Iniciar navegación asistida en AppState
    state.startNavigation(destName);
  }

  void _recenterUser() {
    _mapController.move(_userLocation, 17.0);
    context.read<AppState>().speak("Centrando mapa en tu ubicación actual.");
    context.read<AppState>().vibrate(30);
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final currentStep = state.currentNavStep;
    final isNavigating = state.isNavigating;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. LIENZO INTERACTIVO DEL MAPA (OpenStreetMap / CartoDB)
          _buildMapCanvas(state),

          // 2. BARRA DE BÚSQUEDA ESTILO GOOGLE MAPS (Superior Flotante)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildGoogleMapsSearchBar(state),
                  if (!_isSearchFocused) _buildCategoryFilterChips(state),
                ],
              ),
            ),
          ),

          // 3. DESPLEGABLE DE SUGERENCIAS / RESULTADOS DE BÚSQUEDA
          if (_isSearchFocused)
            Positioned(
              top: 110,
              left: 14,
              right: 14,
              bottom: 120,
              child: _buildSearchSuggestionsList(state),
            ),

          // 4. BOTONES FLOTANTES DE CONTROL DEL MAPA (Zoom, Mi Ubicación, Capa)
          if (!_isSearchFocused)
            Positioned(
              right: 14,
              bottom: _isPanelCollapsed ? 120 : 340,
              child: _buildMapControls(),
            ),

          // 5. TARJETA FLOTANTE INFERIOR DE DIRECCIÓN Y NAVEGACIÓN PASO A PASO
          if (!_isSearchFocused && currentStep != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 84, // Por encima de la barra de navegación principal
              child: _buildNavigationTurnCard(state, currentStep, isNavigating),
            ),
        ],
      ),
    );
  }

  /// Lienzo del Mapa con FlutterMap
  Widget _buildMapCanvas(AppState state) {
    final tileUrl = _useDarkMap
        ? "https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png"
        : "https://tile.openstreetmap.org/{z}/{x}/{y}.png";

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _userLocation,
        initialZoom: 16.5,
        minZoom: 12.0,
        maxZoom: 19.0,
        onTap: (_, __) {
          if (_isSearchFocused) {
            setState(() => _isSearchFocused = false);
            FocusScope.of(context).unfocus();
          }
        },
      ),
      children: [
        // Capa de Mosaicos de Calles (OpenStreetMap)
        TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: 'com.example.riqsi',
          maxZoom: 19,
        ),

        // Línea de Ruta Peatonal (Polyline)
        if (_routePolyline.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePolyline,
                color: RiqsiTheme.accentCyan,
                strokeWidth: 6.0,
                borderColor: Colors.black45,
                borderStrokeWidth: 2.0,
              ),
            ],
          ),

        // Marcadores: Usuario y Destino
        MarkerLayer(
          markers: [
            // Marcador de Ubicación del Usuario (Punto azul pulsante con halo)
            Marker(
              point: _userLocation,
              width: 50,
              height: 50,
              child: _buildUserLocationMarker(),
            ),

            // Marcador del Destino si está seleccionado
            if (_destinationLocation != null)
              Marker(
                point: _destinationLocation!,
                width: 55,
                height: 55,
                child: _buildDestinationMarker(state.activeDestination),
              ),
          ],
        ),
      ],
    );
  }

  /// Marcador de Ubicación del Usuario
  Widget _buildUserLocationMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Halo exterior translúcido
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: RiqsiTheme.accentCyan.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
        ),
        // Círculo blanco de contraste
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.black54, blurRadius: 6),
            ],
          ),
        ),
        // Núcleo cian de posición GPS
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

  /// Marcador del Destino seleccionado
  Widget _buildDestinationMarker(String name) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFFF2A2A),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 8),
            ],
          ),
          child: const Icon(
            Icons.location_on_rounded,
            size: 20,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  /// Barra de búsqueda superior al estilo Google Maps
  Widget _buildGoogleMapsSearchBar(AppState state) {
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
              // Icono de Búsqueda
              const Icon(Icons.search_rounded, color: RiqsiTheme.accentCyan, size: 24),
              const SizedBox(width: 10),

              // Campo de Texto de Destino
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  onTap: () {
                    setState(() {
                      _isSearchFocused = true;
                    });
                  },
                  onChanged: _onSearchChanged,
                  decoration: const InputDecoration(
                    hintText: "Buscar destino o dirección...",
                    hintStyle: TextStyle(color: Colors.white54, fontSize: 15),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

              // Botón de Limpiar o Búsqueda por Voz
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged("");
                    setState(() {
                      _destinationLocation = null;
                      _routePolyline.clear();
                    });
                  },
                )
              else
                IconButton(
                  icon: const Icon(Icons.mic_rounded, color: RiqsiTheme.accentCyan, size: 22),
                  tooltip: "Búsqueda por voz",
                  onPressed: () {
                    state.speak("Dime qué lugar deseas buscar.");
                    state.vibrate(30);
                  },
                ),

              // Botón de Enlace API
              IconButton(
                icon: const Icon(Icons.api_rounded, color: RiqsiTheme.accentCyan, size: 22),
                tooltip: "Enlace API",
                onPressed: () => _showApiModal(state),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  /// Chips de Categorías Rápidas (Farmacias, Paraderos, Mercados, Mi Casa)
  Widget _buildCategoryFilterChips(AppState state) {
    final categories = [
      {"label": "Farmacias", "icon": Icons.local_pharmacy_rounded, "q": "Farmacia"},
      {"label": "Paraderos", "icon": Icons.directions_bus_rounded, "q": "Paradero"},
      {"label": "Mercados", "icon": Icons.shopping_basket_rounded, "q": "Metro"},
      {"label": "Mi Casa", "icon": Icons.home_rounded, "q": "Casa"},
    ];

    return Container(
      margin: const EdgeInsets.only(top: 8),
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final label = cat["label"] as String;
          final icon = cat["icon"] as IconData;
          final query = cat["q"] as String;

          return InkWell(
            onTap: () {
              final results = _apiDataSource.searchPlaces(query);
              if (results.isNotEmpty) {
                _selectDestination(results.first, state);
              }
            },
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white24, width: 1),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4),
                ],
              ),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: RiqsiTheme.accentCyan),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
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

  /// Lista de Sugerencias de Búsqueda
  Widget _buildSearchSuggestionsList(AppState state) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141923).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: RiqsiTheme.accentCyan.withValues(alpha: 0.4)),
            boxShadow: const [
              BoxShadow(color: Colors.black87, blurRadius: 16),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Lugares y Destinos Sugeridos",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                      onPressed: () {
                        setState(() => _isSearchFocused = false);
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    final name = item["name"] as String;
                    final address = item["address"] as String;
                    final dist = "${item["distance"]} m";

                    return ListTile(
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
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        address,
                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                      trailing: Text(
                        dist,
                        style: const TextStyle(
                          color: RiqsiTheme.accentCyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => _selectDestination(item, state),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Botones Flotantes de Control del Mapa (Zoom, Mi Ubicación, Capa)
  Widget _buildMapControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Botón Mi Ubicación
        _buildCircleButton(
          icon: Icons.my_location_rounded,
          tooltip: "Mi Ubicación Actual",
          color: RiqsiTheme.accentCyan,
          onTap: _recenterUser,
        ),
        const SizedBox(height: 8),

        // Botón Capa Oscura / Estándar
        _buildCircleButton(
          icon: _useDarkMap ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          tooltip: "Alternar modo mapa",
          color: Colors.white,
          onTap: () {
            setState(() => _useDarkMap = !_useDarkMap);
          },
        ),
        const SizedBox(height: 8),

        // Zoom In (+)
        _buildCircleButton(
          icon: Icons.add_rounded,
          tooltip: "Acercar mapa",
          color: Colors.white,
          onTap: () {
            final z = _mapController.camera.zoom + 1.0;
            _mapController.move(_mapController.camera.center, z);
          },
        ),
        const SizedBox(height: 8),

        // Zoom Out (-)
        _buildCircleButton(
          icon: Icons.remove_rounded,
          tooltip: "Alejar mapa",
          color: Colors.white,
          onTap: () {
            final z = _mapController.camera.zoom - 1.0;
            _mapController.move(_mapController.camera.center, z);
          },
        ),
      ],
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF161B26).withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1.2),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 8),
            ],
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }

  /// Tarjeta Flotante Inferior de Orientación Sensorial y Botones de las 4 Maniobras
  Widget _buildNavigationTurnCard(
    AppState state,
    NavigationStep step,
    bool isNavigating,
  ) {
    final visual = _getDirectionVisuals(step.direction);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121722).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: visual.color, width: 2),
            boxShadow: [
              BoxShadow(
                color: visual.color.withValues(alpha: 0.25),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Barra Superior de la Tarjeta con Maniobra y Botón de Voz
              Row(
                children: [
                  // Icono de Maniobra
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: visual.color, width: 2),
                    ),
                    child: Icon(visual.icon, color: visual.color, size: 34),
                  ),
                  const SizedBox(width: 14),

                  // Texto de Maniobra y Metros
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.directionTitle,
                          style: TextStyle(
                            color: visual.color,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${step.distanceMeters} metros • ${step.streetName}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Botón de Repetir Voz
                  IconButton(
                    onPressed: state.repeatNavInstruction,
                    icon: const Icon(Icons.volume_up_rounded, color: RiqsiTheme.accentCyan, size: 28),
                    tooltip: "Repetir indicación de voz",
                  ),

                  // Botón de Colapsar/Expandir
                  IconButton(
                    onPressed: () {
                      setState(() => _isPanelCollapsed = !_isPanelCollapsed);
                    },
                    icon: Icon(
                      _isPanelCollapsed ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),

              // Contenido Expandido: Instrucción y 4 Botones Táctiles para el API
              if (!_isPanelCollapsed) ...[
                const SizedBox(height: 8),
                Text(
                  step.instruction,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),

                // LOS 4 BOTONES DE MANIOBRA DEL API: DE FRENTE, DERECHA, IZQUIERDA, ATRÁS
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniDirectionButton(
                        "FRENTE",
                        NavDirection.straight,
                        RiqsiTheme.accentCyan,
                        Icons.arrow_upward_rounded,
                        () => state.setNavDirection(
                          NavDirection.straight,
                          customInstruction: "Continúa de frente. Acera despejada.",
                          distanceMeters: 25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildMiniDirectionButton(
                        "DERECHA",
                        NavDirection.right,
                        const Color(0xFF00E676),
                        Icons.arrow_forward_rounded,
                        () => state.setNavDirection(
                          NavDirection.right,
                          customInstruction: "Gira a la derecha en la próxima esquina.",
                          distanceMeters: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildMiniDirectionButton(
                        "IZQUIERDA",
                        NavDirection.left,
                        const Color(0xFFB388FF),
                        Icons.arrow_back_rounded,
                        () => state.setNavDirection(
                          NavDirection.left,
                          customInstruction: "Gira a la izquierda con precaución.",
                          distanceMeters: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildMiniDirectionButton(
                        "ATRÁS",
                        NavDirection.back,
                        const Color(0xFFFF5252),
                        Icons.u_turn_left_rounded,
                        () => state.setNavDirection(
                          NavDirection.back,
                          customInstruction: "Da media vuelta. Ve hacia atrás para retomar tu ruta.",
                          distanceMeters: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniDirectionButton(
    String label,
    NavDirection dir,
    Color color,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showApiModal(AppState state) {
    final controller = TextEditingController(text: state.navigationApiUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.api_rounded, color: RiqsiTheme.accentCyan),
            SizedBox(width: 8),
            Text("API de Navegación", style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "URL del backend para cálculo de rutas y direcciones en tiempo real:",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.black38,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                hintText: "http://10.247.64.45:8765/api/route",
                hintStyle: const TextStyle(color: Colors.white30),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              state.testNavApiConnection();
            },
            child: const Text("Probar Conexión", style: TextStyle(color: RiqsiTheme.accentCyan)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: RiqsiTheme.accentCyan,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              state.updateNavApiUrl(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  _DirectionVisuals _getDirectionVisuals(NavDirection dir) {
    switch (dir) {
      case NavDirection.straight:
        return _DirectionVisuals(color: RiqsiTheme.accentCyan, icon: Icons.arrow_upward_rounded);
      case NavDirection.right:
        return _DirectionVisuals(color: const Color(0xFF00E676), icon: Icons.arrow_forward_rounded);
      case NavDirection.left:
        return _DirectionVisuals(color: const Color(0xFFB388FF), icon: Icons.arrow_back_rounded);
      case NavDirection.back:
        return _DirectionVisuals(color: const Color(0xFFFF5252), icon: Icons.u_turn_left_rounded);
      case NavDirection.arrived:
        return _DirectionVisuals(color: const Color(0xFFFFD600), icon: Icons.check_circle_rounded);
    }
  }
}

class _DirectionVisuals {
  final Color color;
  final IconData icon;

  _DirectionVisuals({required this.color, required this.icon});
}
