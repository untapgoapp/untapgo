import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class EventMapPreview extends StatelessWidget {
  final double lat;
  final double lng;

  const EventMapPreview({
    super.key,
    required this.lat,
    required this.lng,
  });

  Future<void> _openMaps() async {
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final position = LatLng(lat, lng);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 180,
        child: Stack(
          children: [

            /// Google Map (visual only)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: position,
                zoom: 14,
              ),
              markers: {
                Marker(
                  markerId: const MarkerId('event'),
                  position: position,
                ),
              },
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              liteModeEnabled: true,
            ),

            /// Transparent layer that captures taps
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openMaps,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}