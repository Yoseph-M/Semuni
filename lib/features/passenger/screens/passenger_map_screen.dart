import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/passenger_route.dart';
import '../../../navigation/app_routes.dart';
import '../../../repositories/passenger_route_repository.dart';
import '../widgets/passenger_bottom_nav.dart';

/// SMUNI Passenger Map & Route Discovery Screen.
///
/// Allows passengers to:
/// 1. Browse a mock visual representation of Addis Ababa taxi stations.
/// 2. Search for a destination.
/// 3. View taxi routes serving that destination.
/// 4. Tap a route to view detailed information.
/// 5. Proceed to ride booking.
///
/// Architecture: PassengerMapScreen → PassengerRouteRepository → MockPassengerRouteService
class PassengerMapScreen extends StatefulWidget {
  const PassengerMapScreen({super.key, this.passengerRouteRepository});

  final PassengerRouteRepository? passengerRouteRepository;

  @override
  State<PassengerMapScreen> createState() => _PassengerMapScreenState();
}

class _PassengerMapScreenState extends State<PassengerMapScreen> {
  late final PassengerRouteRepository _repository;
  late final TextEditingController _searchController;

  /// All stations loaded from the repository.
  List<TaxiStation> _stations = [];

  /// Currently displayed routes (search results or destination routes).
  List<PassengerRoute> _routes = [];

  /// The currently selected destination station (null = no selection).
  TaxiStation? _selectedStation;

  /// Whether the data is loading.
  bool _isLoading = false;

  /// Whether a search has been attempted.
  bool _hasSearched = false;

  /// Whether stations have been loaded.
  bool _stationsLoaded = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.passengerRouteRepository ?? PassengerRouteRepository();
    _searchController = TextEditingController();
    _loadStations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStations() async {
    setState(() => _isLoading = true);
    try {
      final stations = await _repository.getStations();
      if (mounted) {
        setState(() {
          _stations = stations;
          _stationsLoaded = true;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _searchDestination(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _routes = [];
        _hasSearched = false;
        _selectedStation = null;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _selectedStation = null;
    });
    try {
      final results = await _repository.searchByDestination(query);
      if (mounted) {
        setState(() {
          _routes = results;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectStation(TaxiStation station) async {
    setState(() {
      _selectedStation = station;
      _searchController.text = station.name;
      _isLoading = true;
      _hasSearched = true;
    });
    try {
      final results = await _repository.getRoutesToStation(station.id);
      if (mounted) {
        setState(() {
          _routes = results;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _routes = [];
      _hasSearched = false;
      _selectedStation = null;
    });
  }

  void _showRouteDetails(PassengerRoute route) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteDetailSheet(route: route),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            _MapHeader(onClearSearch: _clearSearch),

            // ── Mock Map Area ────────────────────────────────────────────────
            Flexible(
              flex: 5,
              child: _MockMapCanvas(
                stations: _stations,
                selectedStation: _selectedStation,
                stationsLoaded: _stationsLoaded,
                onStationTap: _selectStation,
              ),
            ),

            // ── Search Bar ───────────────────────────────────────────────────
            _SearchPanel(
              controller: _searchController,
              onChanged: _searchDestination,
              onClear: _clearSearch,
            ),

            // ── Results Panel ────────────────────────────────────────────────
            Flexible(
              flex: 4,
              child: _ResultsPanel(
                routes: _routes,
                isLoading: _isLoading,
                hasSearched: _hasSearched,
                selectedStation: _selectedStation,
                onRouteTap: _showRouteDetails,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _MapHeader extends StatelessWidget {
  const _MapHeader({this.onClearSearch});

  final VoidCallback? onClearSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.screenHorizontalPadding,
        vertical: AppConstants.spacingSm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          // Back button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (Navigator.canPop(context)) {
                  Navigator.of(context).pop();
                }
              },
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: AppConstants.iconLg,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spacingXs),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Taxi Map',
                  style: AppTextStyles.headlineSmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Addis Ababa · Mock Network',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Map legend chip
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingSm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  size: 12,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Demo Data',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mock Map Canvas
// ---------------------------------------------------------------------------

class _MockMapCanvas extends StatelessWidget {
  const _MockMapCanvas({
    required this.stations,
    required this.selectedStation,
    required this.stationsLoaded,
    required this.onStationTap,
  });

  final List<TaxiStation> stations;
  final TaxiStation? selectedStation;
  final bool stationsLoaded;
  final ValueChanged<TaxiStation> onStationTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(color: Color(0xFFE8F0EB)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return Stack(
            children: [
              // Grid/road background
              CustomPaint(
                painter: _MapGridPainter(),
                child: const SizedBox.expand(),
              ),

              // Route lines between connected stations
              if (stationsLoaded)
                CustomPaint(
                  painter: _RouteLinesPainter(
                    stations: stations,
                    selectedStationId: selectedStation?.id,
                  ),
                  child: const SizedBox.expand(),
                ),

              // Station markers — computed here so Positioned is a direct
              // Stack child (LayoutBuilder is the Stack's parent, not a child).
              if (stationsLoaded)
                ...stations.map((station) {
                  const markerSize = 10.0;
                  const hubSize = 14.0;
                  final size = station.isHub ? hubSize : markerSize;
                  final x = w * station.mapX;
                  final y = h * station.mapY;
                  final isSelected = selectedStation?.id == station.id;

                  return Positioned(
                    left: x - size / 2 - (isSelected ? size * 0.4 : 0),
                    top: y - size / 2 - (isSelected ? size * 0.4 : 0),
                    child: GestureDetector(
                      onTap: () => onStationTap(station),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: AppConstants.animNormal,
                            width: isSelected ? size * 1.8 : size,
                            height: isSelected ? size * 1.8 : size,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : station.isHub
                                  ? AppColors.primaryLight
                                  : AppColors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary,
                                width: isSelected ? 0 : 2.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: isSelected ? 8 : 4,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.surface.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(3),
                              boxShadow: const [
                                BoxShadow(
                                  color: AppColors.shadow,
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            child: Text(
                              station.label,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: isSelected
                                    ? AppColors.textOnPrimary
                                    : AppColors.textPrimary,
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

              // "Your location" pin in the center
              const Positioned.fill(child: _CurrentLocationPin()),

              // Map attribution label
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  ),
                  child: Text(
                    'Tap a station to explore routes',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Paints a subtle road-grid background on the mock map.
class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = const Color(0xFFD0DDD4)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final majorRoadPaint = Paint()
      ..color = const Color(0xFFC2D3C7)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    // Horizontal grid lines
    for (double y = 0.2; y <= 0.9; y += 0.15) {
      canvas.drawLine(
        Offset(0, size.height * y),
        Offset(size.width, size.height * y),
        y == 0.5 ? majorRoadPaint : roadPaint,
      );
    }

    // Vertical grid lines
    for (double x = 0.15; x <= 0.95; x += 0.15) {
      canvas.drawLine(
        Offset(size.width * x, 0),
        Offset(size.width * x, size.height),
        x == 0.5 ? majorRoadPaint : roadPaint,
      );
    }

    // Diagonal road (ring road effect)
    final diagonalPaint = Paint()
      ..color = const Color(0xFFBFCFC4)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(size.width * 0.1, size.height * 0.3),
      Offset(size.width * 0.9, size.height * 0.75),
      diagonalPaint,
    );

    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.7),
      Offset(size.width * 0.85, size.height * 0.2),
      diagonalPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MapGridPainter oldDelegate) => false;
}

/// Paints route lines between connected stations.
class _RouteLinesPainter extends CustomPainter {
  const _RouteLinesPainter({
    required this.stations,
    required this.selectedStationId,
  });

  final List<TaxiStation> stations;
  final String? selectedStationId;

  // Pairs of station IDs representing connections.
  static const List<(String, String)> _connections = [
    ('bole', 'megenagna'),
    ('megenagna', 'cmc'),
    ('megenagna', 'ayat'),
    ('bole', 'mexico'),
    ('mexico', 'piazza'),
    ('mexico', 'merkato'),
    ('piazza', 'merkato'),
    ('merkato', 'torhailoch'),
    ('merkato', 'saris'),
    ('torhailoch', 'saris'),
    ('saris', 'kaliti'),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final stationMap = {for (final s in stations) s.id: s};

    for (final (fromId, toId) in _connections) {
      final from = stationMap[fromId];
      final to = stationMap[toId];
      if (from == null || to == null) continue;

      final isHighlighted =
          selectedStationId == fromId || selectedStationId == toId;

      final paint = Paint()
        ..color = isHighlighted
            ? AppColors.primary.withValues(alpha: 0.7)
            : AppColors.primary.withValues(alpha: 0.25)
        ..strokeWidth = isHighlighted ? 3.0 : 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(size.width * from.mapX, size.height * from.mapY),
        Offset(size.width * to.mapX, size.height * to.mapY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RouteLinesPainter oldDelegate) =>
      oldDelegate.selectedStationId != selectedStationId;
}

/// "You are here" pin shown at the centre of the mock map.
class _CurrentLocationPin extends StatelessWidget {
  const _CurrentLocationPin();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0.0, 0.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.35),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              'You',
              style: AppTextStyles.labelSmall.copyWith(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search Panel
// ---------------------------------------------------------------------------

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(
        AppConstants.screenHorizontalPadding,
        AppConstants.spacingMd,
        AppConstants.screenHorizontalPadding,
        AppConstants.spacingMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Where do you want to go?',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. Piazza, Bole, Megenagna...',
              hintStyle: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textHint,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.primary,
              ),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: onClear,
                    tooltip: 'Clear search',
                  );
                },
              ),
              filled: true,
              fillColor: AppColors.inputFill,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMd,
                vertical: AppConstants.spacingSm,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                borderSide: const BorderSide(color: AppColors.inputBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                borderSide: const BorderSide(color: AppColors.inputBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                borderSide: const BorderSide(
                  color: AppColors.inputFocusBorder,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results Panel
// ---------------------------------------------------------------------------

class _ResultsPanel extends StatelessWidget {
  const _ResultsPanel({
    required this.routes,
    required this.isLoading,
    required this.hasSearched,
    required this.selectedStation,
    required this.onRouteTap,
  });

  final List<PassengerRoute> routes;
  final bool isLoading;
  final bool hasSearched;
  final TaxiStation? selectedStation;
  final ValueChanged<PassengerRoute> onRouteTap;

  @override
  Widget build(BuildContext context) {
    if (!hasSearched) {
      return _HintPanel();
    }

    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppConstants.spacingXl),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (routes.isEmpty) {
      return _EmptyResultsPanel(selectedStation: selectedStation);
    }

    return _RouteList(
      routes: routes,
      selectedStation: selectedStation,
      onRouteTap: onRouteTap,
    );
  }
}

class _HintPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.screenHorizontalPadding,
        vertical: AppConstants.spacingMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Popular Destinations',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Wrap(
            spacing: AppConstants.spacingXs,
            runSpacing: AppConstants.spacingXs,
            children: [
              'Piazza',
              'Bole',
              'Megenagna',
              'Mexico',
              'Merkato',
              'Saris',
              'CMC',
              'Ayat',
            ].map((name) => _DestinationChip(label: name)).toList(),
          ),
        ],
      ),
    );
  }
}

class _DestinationChip extends StatelessWidget {
  const _DestinationChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      labelStyle: AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
      backgroundColor: AppColors.primaryTint,
      side: const BorderSide(color: AppColors.border),
      onPressed: () {
        // Find the search controller and apply the label.
        // We bubble through the ancestor state.
        final state = context
            .findAncestorStateOfType<_PassengerMapScreenState>();
        if (state != null) {
          state._searchController.text = label;
          state._searchDestination(label);
        }
      },
    );
  }
}

class _EmptyResultsPanel extends StatelessWidget {
  const _EmptyResultsPanel({required this.selectedStation});

  final TaxiStation? selectedStation;

  @override
  Widget build(BuildContext context) {
    final label = selectedStation?.name ?? 'your search';
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingXl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.directions_bus_outlined,
            size: 40,
            color: AppColors.textHint,
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            'No routes found for "$label"',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacingXs),
          Text(
            'Try searching for another destination\nor tap a station on the map.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RouteList extends StatelessWidget {
  const _RouteList({
    required this.routes,
    required this.selectedStation,
    required this.onRouteTap,
  });

  final List<PassengerRoute> routes;
  final TaxiStation? selectedStation;
  final ValueChanged<PassengerRoute> onRouteTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.screenHorizontalPadding,
            AppConstants.spacingMd,
            AppConstants.screenHorizontalPadding,
            AppConstants.spacingXs,
          ),
          child: Text(
            selectedStation != null
                ? 'Routes to ${selectedStation!.name}'
                : 'Matching Routes',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.screenHorizontalPadding,
              vertical: AppConstants.spacingXs,
            ),
            itemCount: routes.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppConstants.spacingXs),
            itemBuilder: (_, index) => _RouteCard(
              route: routes[index],
              onTap: () => onRouteTap(routes[index]),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Route Card
// ---------------------------------------------------------------------------

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route, required this.onTap});

  final PassengerRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              // Route icon
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: route.isAvailable
                      ? AppColors.primaryTint
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Center(
                  child: Icon(
                    Icons.directions_bus_rounded,
                    size: AppConstants.iconLg,
                    color: route.isAvailable
                        ? AppColors.primary
                        : AppColors.textHint,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spacingMd),

              // Route info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            route.name,
                            style: AppTextStyles.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Status badge
                        _StatusBadge(isAvailable: route.isAvailable),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (route.estimatedDuration != null)
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: AppConstants.iconSm,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              route.estimatedDuration!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (route.routeCode != null) ...[
                            const SizedBox(width: AppConstants.spacingSm),
                            Flexible(
                              child: Text(
                                route.routeCode!,
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.textHint,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),

              const SizedBox(width: AppConstants.spacingSm),

              // Fare + chevron
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'ETB ${route.fare.toStringAsFixed(0)}',
                    style: AppTextStyles.amountSmall.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: AppConstants.iconMd,
                    color: AppColors.textHint,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isAvailable});

  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isAvailable
            ? AppColors.successContainer
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        isAvailable ? 'Active' : 'Limited',
        style: AppTextStyles.labelSmall.copyWith(
          color: isAvailable ? AppColors.success : AppColors.textHint,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Route Detail Bottom Sheet
// ---------------------------------------------------------------------------

class _RouteDetailSheet extends StatelessWidget {
  const _RouteDetailSheet({required this.route});

  final PassengerRoute route;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusXl),
            ),
          ),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              // Drag handle
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppConstants.spacingMd),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.screenHorizontalPadding,
                    AppConstants.spacingMd,
                    AppConstants.screenHorizontalPadding,
                    AppConstants.spacingSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              route.name,
                              style: AppTextStyles.headlineMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _StatusBadge(isAvailable: route.isAvailable),
                        ],
                      ),
                      if (route.routeCode != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          route.routeCode!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Container(height: 1, color: AppColors.divider),
              ),

              // Detail rows
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(
                    AppConstants.screenHorizontalPadding,
                  ),
                  child: Column(
                    children: [
                      // From / To
                      _RouteDetailRow(
                        icon: Icons.radio_button_on_rounded,
                        iconColor: AppColors.success,
                        label: 'From',
                        value: route.startLabel,
                      ),
                      _RouteDetailRow(
                        icon: Icons.location_on_rounded,
                        iconColor: AppColors.error,
                        label: 'To',
                        value: route.endLabel,
                      ),
                      const SizedBox(height: AppConstants.spacingXs),

                      // Fare
                      _RouteDetailRow(
                        icon: Icons.payments_outlined,
                        iconColor: AppColors.primary,
                        label: 'Fare',
                        value: 'ETB ${route.fare.toStringAsFixed(2)}',
                        valueBold: true,
                      ),

                      // Duration
                      if (route.estimatedDuration != null)
                        _RouteDetailRow(
                          icon: Icons.access_time_rounded,
                          iconColor: AppColors.textSecondary,
                          label: 'Duration',
                          value: route.estimatedDuration!,
                        ),

                      // Distance
                      if (route.distanceKm != null)
                        _RouteDetailRow(
                          icon: Icons.straighten_rounded,
                          iconColor: AppColors.textSecondary,
                          label: 'Distance',
                          value: '${route.distanceKm!.toStringAsFixed(1)} km',
                        ),

                      // Operating hours
                      if (route.operatingHours != null)
                        _RouteDetailRow(
                          icon: Icons.schedule_rounded,
                          iconColor: AppColors.textSecondary,
                          label: 'Hours',
                          value: route.operatingHours!,
                        ),

                      // Stops
                      if (route.intermediateStops.isNotEmpty) ...[
                        const SizedBox(height: AppConstants.spacingMd),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Intermediate Stops',
                            style: AppTextStyles.titleSmall.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingXs),
                        Wrap(
                          spacing: AppConstants.spacingXs,
                          runSpacing: AppConstants.spacingXs,
                          children: route.intermediateStops.map((stop) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppConstants.spacingSm,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(
                                  AppConstants.radiusFull,
                                ),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(
                                stop,
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      // Instructions
                      if (route.instructions != null) ...[
                        const SizedBox(height: AppConstants.spacingMd),
                        Container(
                          padding: const EdgeInsets.all(AppConstants.spacingMd),
                          decoration: BoxDecoration(
                            color: AppColors.primaryTint,
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusMd,
                            ),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: AppConstants.iconMd,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: AppConstants.spacingSm),
                              Expanded(
                                child: Text(
                                  route.instructions!,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: AppConstants.spacingXl),

                      // Book Ride CTA
                      SizedBox(
                        width: double.infinity,
                        height: AppConstants.minTouchTarget + 4,
                        child: ElevatedButton.icon(
                          onPressed: route.isAvailable
                              ? () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).pushNamed(
                                    AppRoutes.passengerBookRide,
                                    arguments: route,
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            route.isAvailable
                                ? 'Continue to Booking'
                                : 'Route Unavailable',
                            style: AppTextStyles.labelLarge,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.textOnPrimary,
                            disabledBackgroundColor: AppColors.surfaceVariant,
                            disabledForegroundColor: AppColors.textHint,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusMd,
                              ),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),

                      const SizedBox(height: AppConstants.spacingMd),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RouteDetailRow extends StatelessWidget {
  const _RouteDetailRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueBold = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool valueBold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppConstants.iconMd, color: iconColor),
          const SizedBox(width: AppConstants.spacingMd),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: valueBold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
