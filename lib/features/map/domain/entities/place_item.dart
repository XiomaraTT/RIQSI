import 'package:latlong2/latlong.dart';

class PlaceItem {
  final String id;
  final String name;
  final String address;
  final LatLng location;
  final String category;
  final int distanceMeters;

  const PlaceItem({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    required this.category,
    required this.distanceMeters,
  });
}
