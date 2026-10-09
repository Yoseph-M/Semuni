import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gebeta_gl/gebeta_gl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/passenger_route.dart';
import '../../../services/api/maps_api_service.dart';

/// Interactive Gebeta Maps Canvas for the semuni Passenger Discovery Screen.
///
/// Integrates real Gebeta vector map tiles, GPS-located taxi stations across
/// Addis Ababa, route polylines, and smooth camera navigation.
class GebetaMapCanvas extends StatefulWidget {
  const GebetaMapCanvas({
    super.key,
    required this.stations,
    required this.selectedStation,
    required this.stationsLoaded,
    required this.onStationTap,
    this.onCurrentLocationTap,
    this.mapsApiService,
    this.fallbackWidget,
  });

  final List<TaxiStation> stations;
  final TaxiStation? selectedStation;
  final bool stationsLoaded;
  final ValueChanged<TaxiStation> onStationTap;
  final VoidCallback? onCurrentLocationTap;
  final MapsApiService? mapsApiService;
  final Widget? fallbackWidget;

  @override
  State<GebetaMapCanvas> createState() => _GebetaMapCanvasState();
}

class _GebetaMapCanvasState extends State<GebetaMapCanvas> {
  GebetaMapController? _mapController;
  bool _isMapReady = false;
  Line? _activeRouteLine;
  final Map<String, Symbol> _stationSymbols = {};

  // Addis Ababa coordinates
  static const _defaultCenter = LatLng(9.0222, 38.7468);
  static const _defaultZoom = 12.0;

  bool get _isGebetaGlSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Timer? _loadTimeoutTimer;

  @override
  void initState() {
    super.initState();
    if (!_isGebetaGlSupported) {
      _isMapReady = true;
      return;
    }

    // Safety watchdog for supported mobile platforms: If Gebeta map tiles
    // don't finish loading within 3.5s, seamlessly fall back to schematic map.
    _loadTimeoutTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && !_isMapReady) {
        setState(() {
          _isMapReady = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _loadTimeoutTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GebetaMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedStation?.id != widget.selectedStation?.id) {
      _onSelectedStationChanged();
    }
    if (!oldWidget.stationsLoaded && widget.stationsLoaded) {
      _addStationMarkers();
    }
  }

  void _onMapCreated(GebetaMapController controller) {
    _loadTimeoutTimer?.cancel();
    _mapController = controller;
    setState(() => _isMapReady = true);

    controller.onSymbolTapped.add(_handleSymbolTapped);
    if (widget.stationsLoaded) {
      _addStationMarkers();
    }
  }

  void _handleSymbolTapped(Symbol symbol) {
    final stationId = symbol.data?['stationId'] as String?;
    if (stationId != null) {
      final station = widget.stations.firstWhere(
        (s) => s.id == stationId,
        orElse: () => widget.stations.first,
      );
      widget.onStationTap(station);
    }
  }

  Future<void> _addStationMarkers() async {
    final controller = _mapController;
    if (controller == null || !widget.stationsLoaded) return;

    try {
      await controller.clearSymbols();
      _stationSymbols.clear();

      for (final station in widget.stations) {
        final lat = station.latitude;
        final lon = station.longitude;
        if (lat == null || lon == null) continue;

        final isSelected = widget.selectedStation?.id == station.id;
        final symbol = await controller.addSymbol(
          SymbolOptions(
            geometry: LatLng(lat, lon),
            iconImage: 'marker-15',
            iconSize: isSelected ? 1.5 : (station.isHub ? 1.2 : 0.9),
            textField: station.label,
            textSize: 11.0,
            textOffset: const Offset(0, 1.2),
            textColor: '#0B2B1B',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.5,
          ),
          {'stationId': station.id},
        );
        _stationSymbols[station.id] = symbol;
      }
    } catch (_) {
      // Symbols can fail gracefully without crashing
    }
  }

  Future<void> _onSelectedStationChanged() async {
    final station = widget.selectedStation;
    final controller = _mapController;
    if (controller == null || station == null) return;

    final lat = station.latitude;
    final lon = station.longitude;
    if (lat != null && lon != null) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(lat, lon), 14.0),
      );
    }
    await _addStationMarkers();
  }

  Future<void> drawRoutePolyline(List<LatLng> points) async {
    final controller = _mapController;
    if (controller == null || points.isEmpty) return;
    try {
      if (_activeRouteLine != null) {
        await controller.clearLines();
      }
      _activeRouteLine = await controller.addLine(
        LineOptions(
          geometry: points,
          lineColor: '#0E7A4A',
          lineWidth: 4.5,
          lineOpacity: 0.9,
        ),
      );
    } catch (_) {}
  }

  void _recenterMap() {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_defaultCenter, _defaultZoom),
    );
  }

  void _zoomIn() {
    _mapController?.animateCamera(CameraUpdate.zoomIn());
  }

  void _zoomOut() {
    _mapController?.animateCamera(CameraUpdate.zoomOut());
  }

  @override
  Widget build(BuildContext context) {
    // Gebeta GL plugin only supports mobile (Android & iOS).
    // On macOS, Windows, Linux, and Web, always render the interactive schematic map.
    if (!_isGebetaGlSupported) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: const Color(0xFFE8F0EB),
            alignment: Alignment.center,
            child: Text(
              'Gebeta Maps is available on Android and iOS.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        GebetaMap(
          initialCameraPosition: const CameraPosition(
            target: _defaultCenter,
            zoom: _defaultZoom,
          ),
          styleString: 'https://tiles.gebeta.app/style.json',
          onMapCreated: _onMapCreated,
          myLocationEnabled: false,
          trackCameraPosition: true,
          compassEnabled: true,
        ),

        // Floating Map Controls (Zoom in/out, Recenter)
        Positioned(
          bottom: 16,
          right: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildControlButton(
                icon: Icons.my_location_rounded,
                tooltip: 'Recenter Addis Ababa',
                onTap: _recenterMap,
              ),
              const SizedBox(height: 8),
              _buildControlButton(
                icon: Icons.add_rounded,
                tooltip: 'Zoom In',
                onTap: _zoomIn,
              ),
              const SizedBox(height: 4),
              _buildControlButton(
                icon: Icons.remove_rounded,
                tooltip: 'Zoom Out',
                onTap: _zoomOut,
              ),
            ],
          ),
        ),

        // Loading overlay if map is initializing
        if (!_isMapReady)
          Container(
            color: const Color(0xFFE8F0EB),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppConstants.spacingSm),
                Text(
                  'Loading Gebeta Maps...',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXs),
                TextButton.icon(
                  onPressed: () {
                    _loadTimeoutTimer?.cancel();
                    setState(() {
                      _isMapReady = true;
                    });
                  },
                  icon: const Icon(
                    Icons.alt_route_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  label: const Text('Retry Gebeta Maps'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7.0),
          child: Icon(icon, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
