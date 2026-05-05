import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A reusable wrapper around [GoogleMap] that accepts polylines, markers and
/// an optional initial camera target.
class MapWidget extends StatelessWidget {
  final LatLng initialTarget;
  final double initialZoom;
  final Set<Polyline> polylines;
  final Set<Marker> markers;
  final void Function(GoogleMapController)? onMapCreated;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;

  const MapWidget({
    super.key,
    required this.initialTarget,
    this.initialZoom = 12,
    this.polylines = const {},
    this.markers = const {},
    this.onMapCreated,
    this.myLocationEnabled = false,
    this.myLocationButtonEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: initialTarget,
        zoom: initialZoom,
      ),
      polylines: polylines,
      markers: markers,
      onMapCreated: onMapCreated,
      myLocationEnabled: myLocationEnabled,
      myLocationButtonEnabled: myLocationButtonEnabled,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }
}
