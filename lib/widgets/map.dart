import 'dart:async';
import 'dart:math' show min, max, Point;

import 'package:every_door/constants.dart';
import 'package:every_door/helpers/closest_points.dart';
import 'package:every_door/models/amenity.dart';
import 'package:every_door/providers/editor_settings.dart';
import 'package:every_door/providers/geolocation.dart';
import 'package:every_door/providers/imagery.dart';
import 'package:every_door/providers/editor_mode.dart';
import 'package:every_door/providers/legend.dart';
import 'package:every_door/providers/location.dart';
import 'package:every_door/providers/poi_filter.dart';
import 'package:every_door/screens/settings.dart';
import 'package:every_door/widgets/loc_marker.dart';
import 'package:every_door/models/marker_clipper.dart';
import 'package:every_door/widgets/track_button.dart';
import 'package:every_door/widgets/zoom_buttons.dart';
import 'package:every_door/models/diet_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:every_door/helpers/tile_layers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class AmenityMapController {
  Function(LatLng, bool, bool)? moveListener;
  Function(Iterable<LatLng>)? zoomListener;

  setLocation(LatLng location, {bool emitDrag = true, bool onlyIfFar = false}) {
    if (moveListener != null) moveListener!(location, emitDrag, onlyIfFar);
  }

  zoomToFit(Iterable<LatLng> locations) {
    if (locations.isNotEmpty) {
      if (zoomListener != null) zoomListener!(locations);
    }
  }
}

class AmenityMap extends ConsumerStatefulWidget {
  final LatLng initialLocation;
  final List<OsmChange> amenities;
  final List<LatLng> otherObjects;
  final void Function(LatLng)? onDrag;
  final void Function(LatLng)? onDragEnd;
  final void Function(LatLng)? onTrack;
  final void Function(LatLngBounds)? onTap;
  final VoidCallback? onFilterTap;
  final AmenityMapController? controller;
  final bool colorsFromLegend;
  final bool drawNumbers;
  final bool drawZoomButtons;

  const AmenityMap({
    required this.initialLocation,
    this.onDrag,
    this.onDragEnd,
    this.onTrack,
    this.onTap,
    this.onFilterTap,
    this.amenities = const [],
    this.otherObjects = const [],
    this.controller,
    this.drawNumbers = true,
    this.colorsFromLegend = false,
    this.drawZoomButtons = false,
  });

  @override
  ConsumerState createState() => _AmenityMapState();
}

class _AmenityMapState extends ConsumerState<AmenityMap> {
  static const kMapZoom = 17.0;
  static const kMicroZoom = 18.0;

  late final MapController mapController;
  late final StreamSubscription<MapEvent> mapSub;
  late LatLng mapCenter;
  bool showAttribution = true;
  double? savedZoom;

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    mapCenter = widget.initialLocation;
    if (widget.controller != null) {
      widget.controller!.moveListener = onControllerLocation;
      widget.controller!.zoomListener = onControllerZoom;
    }
    mapSub = mapController.mapEventStream.listen(onMapEvent);
    // hideAttribution();
  }

  hideAttribution() {
    Future.delayed(Duration(seconds: 9), () {
      if (showAttribution) {
        setState(() {
          showAttribution = false;
        });
      }
    });
  }

  void onMapEvent(MapEvent event) {
    if (event is MapEventWithMove) {
      mapCenter = event.targetCenter;
      if (event.source != MapEventSource.mapController) {
        ref.read(trackingProvider.notifier).state = false;
        ref.read(zoomProvider.notifier).state = event.zoom;
        if (event.zoom < kEditMinZoom) {
          // Switch navigation mode on
          ref.read(navigationModeProvider.notifier).state = true;
        }
        setState(() {
          // redraw center marker
        });
        if (widget.onDrag != null) widget.onDrag!(event.targetCenter);
      }
    } else if (event is MapEventMoveEnd) {
      if (widget.onDragEnd != null &&
          event.source != MapEventSource.mapController)
        widget.onDragEnd!(event.center);
    } else if (event is MapEventTap) {
      if (widget.onTap != null) {
        widget.onTap!(
            _getBoundsForRadius(event.tapPosition, event.zoom, kTapRadius));
      }
    } else if (event is MapEventRotateEnd) {
      if (event.source != MapEventSource.mapController) {
        double rotation = mapController.rotation;
        while (rotation > 200) rotation -= 360;
        while (rotation < -200) rotation += 360;
        if (rotation.abs() < kRotationThreshold) {
          ref.read(rotationProvider.notifier).state = 0.0;
          mapController.rotate(0.0);
        } else {
          ref.read(rotationProvider.notifier).state = rotation;
        }
      }
    }
  }

  void onControllerLocation(LatLng location, bool emitDrag, bool onlyIfFar) {
    if (onlyIfFar) {
      const maxDist = 1e-7; // degrees
      final center = mapController.center;
      final dist = (center.longitude - location.longitude).abs() +
          (center.latitude - location.latitude).abs();
      if (dist / 2 <= maxDist) return;
    }
    mapController.move(location, mapController.zoom);
    if (emitDrag && widget.onDrag != null) {
      widget.onDrag!(location);
    }
  }

  LatLngBounds _getBoundsForRadius(
      LatLng center, double zoom, double radiusPixels) {
    const crs = Epsg3857();
    final point = crs.latLngToPoint(center, zoom);
    final swPoint =
        crs.pointToLatLng(point - Point(radiusPixels, radiusPixels), zoom);
    final nePoint =
        crs.pointToLatLng(point + Point(radiusPixels, radiusPixels), zoom);
    return LatLngBounds(swPoint, nePoint);
  }

  double _calculateZoom(Iterable<LatLng> locations, EdgeInsets padding) {
    // Add a virtual location to keep center.
    // Here we don't reproject, since on low zooms Mercator could be considered equirectandular.
    // Taking first 9, for we display only 9.
    final bounds = LatLngBounds.fromPoints(locations.take(9).toList());
    final center = mapController.center;
    final dlat = max(
      (bounds.north - center.latitude).abs(),
      (bounds.south - center.latitude).abs(),
    );
    final dlon = max(
      (bounds.east - center.longitude).abs(),
      (bounds.west - center.longitude).abs(),
    );
    final newBounds = LatLngBounds(
      LatLng(center.latitude - dlat, center.longitude - dlon),
      LatLng(center.latitude + dlat, center.longitude + dlon),
    );
    return mapController
        .centerZoomFitBounds(newBounds,
            options: FitBoundsOptions(
              padding: padding,
              maxZoom: kMapZoom + 1,
              inside: false,
            ))
        .zoom;
  }

  onControllerZoom(Iterable<LatLng> locations) {
    const kPadding = EdgeInsets.all(12.0);
    const kZoomThreshold = 0.2;
    const kTooCloseThreshold = 10.0; // meters. I know, bad.

    double zoom = _calculateZoom(locations, kPadding);
    if (zoom < kMapZoom - 1 && locations.length >= 6) {
      // When outliers are too far, we can skip them I guess.
      zoom = _calculateZoom(locations.take(locations.length - 2), kPadding);
    }

    final curZoom = mapController.zoom;
    double maxZoomHere = kMapZoom;
    if (zoom > kMapZoom && zoom > curZoom) {
      // Overzoom only if points are too close.
      if (closestPairDistance(locations) <= kTooCloseThreshold) maxZoomHere++;
    }
    if (zoom < kMapZoom - 1)
      zoom = min(curZoom, kMapZoom - 1);
    else if (zoom > maxZoomHere) zoom = max(curZoom, maxZoomHere);
    if ((zoom - curZoom).abs() >= kZoomThreshold) {
      mapController.move(mapController.center, zoom);
      ref.read(zoomProvider.notifier).state = zoom;
    }
  }

  @override
  void dispose() {
    mapSub.cancel();
    super.dispose();
  }

  Decoration getMarkerDecoration(OsmChange amenity, LegendController legendController) {
    var stops = DietColorsGenerator.getColors(amenity.getFullTags());

    switch (stops.length) {
      case 0:
        return BoxDecoration(
            color: Colors.white
        );
      case 1:
        return BoxDecoration(
            color: stops[0]
        );
      default:
      return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: stops
          )
        );
    }
    //if (!widget.colorsFromLegend) return Colors.white;
    //return legendController.getLegendItem(amenity)?.color ?? kLegendOtherColor;
  }

  IconData getIconFromAmenityType(OsmChange amenity) {
    switch (amenity.getFullTags()['amenity']) {
      case 'cafe':
        return Icons.local_cafe;
      case 'restaurant':
        return Icons.restaurant;
      case 'fast_food':
        return Icons.fastfood;
      default:
        return Icons.question_mark;
    }
  }

  @override
  Widget build(BuildContext context) {
    final LatLng? trackLocation = ref.watch(geolocationProvider);

    // When tracking location, move map and notify the poi list.
    ref.listen<LatLng?>(geolocationProvider, (_, LatLng? location) {
      if (location != null && ref.watch(trackingProvider)) {
        mapController.move(location, mapController.zoom);
        if (widget.onDragEnd != null) widget.onDragEnd!(location);
        if (widget.onTrack != null) widget.onTrack!(location);
      }
    });

    // When turning the tracking on, move the map immediately.
    ref.listen(trackingProvider, (_, bool newState) {
      if (trackLocation != null && newState) {
        mapController.move(trackLocation, mapController.zoom);
        if (widget.onDragEnd != null) widget.onDragEnd!(trackLocation);
        if (widget.onTrack != null) widget.onTrack!(trackLocation);
      }
    });

    // Rotate the map according to the global rotation value.
    ref.listen(rotationProvider, (_, double newValue) {
      if ((newValue - mapController.rotation).abs() >= 1.0) {
        mapController.rotate(newValue);
      }
    });

    // For micromapping, zoom in and out.
    ref.listen<LatLngBounds?>(microZoomedInProvider,
        (_, LatLngBounds? newState) {
      double targetZoom = newState != null
          ? kMicromappingTapZoom
          : (savedZoom ?? mapController.zoom);
      if (newState != null && targetZoom < mapController.zoom)
        targetZoom = mapController.zoom;
      savedZoom = mapController.zoom;
      mapController.move(newState?.center ?? mapController.center, targetZoom);
    });

    // When switching to micromapping, increase zoom.
    ref.listen(editorModeProvider, (_, next) {
      if (next == EditorMode.micromapping) {
        if (mapController.zoom < kMicroZoom) {
          mapController.move(mapController.center, kMicroZoom);
          ref.read(zoomProvider.notifier).state = kMicroZoom;
        }
      }
    });

    // Update colors when the legend is ready.
    ref.listen(legendProvider, (_, next) {
      setState(() {});
    });

    final imagery = ref.watch(selectedImageryProvider);
    final leftHand = ref.watch(editorSettingsProvider).leftHand;
    final iconSize = widget.drawNumbers ? 26.0 : 12.0;
    final legendCon = ref.watch(legendProvider.notifier);
    final loc = AppLocalizations.of(context)!;
    final amenities = List.of(widget.amenities);

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        center: widget.initialLocation, // This does not work :(
        rotation: ref.watch(rotationProvider),
        rotationThreshold: kRotationThreshold,
        // zoom: kMapZoom,
        // colorsFromLegend is an indirect way to know it's micromapping mode.
        zoom: ref.watch(zoomProvider),
        minZoom: kEditMinZoom - 0.1,
        maxZoom: kEditMaxZoom,
        interactiveFlags: ref.watch(microZoomedInProvider) != null
            ? InteractiveFlag.none
            : (InteractiveFlag.drag |
                InteractiveFlag.pinchZoom |
                InteractiveFlag.pinchMove |
                InteractiveFlag.rotate),
        plugins: [
          ZoomButtonsPlugin(),
          OverlayButtonPlugin(),
        ],
      ),
      nonRotatedLayers: [
        // Settings button
        OverlayButtonOptions(
          alignment: leftHand ? Alignment.topRight : Alignment.topLeft,
          padding: EdgeInsets.symmetric(
            horizontal: 0.0,
            vertical: 10.0,
          ),
          icon: Icons.menu,
          tooltip: loc.mapSettings,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => SettingsPage()),
            );
          },
        ),
        // Filter button
        if (widget.onFilterTap != null)
          OverlayButtonOptions(
            alignment: leftHand ? Alignment.topLeft : Alignment.topRight,
            padding: EdgeInsets.symmetric(
              horizontal: 0.0,
              vertical: 10.0,
            ),
            icon: ref.watch(poiFilterProvider).isNotEmpty
                ? Icons.filter_alt
                : Icons.filter_alt_outlined,
            tooltip: loc.mapFilter,
            onPressed: widget.onFilterTap!,
          ),
        // Tracking button
        OverlayButtonOptions(
          alignment: leftHand ? Alignment.topLeft : Alignment.topRight,
          padding: EdgeInsets.symmetric(
            // horizontal: widget.onFilterTap == null ? 0.0 : 50.0,
            horizontal: 0.0,
            vertical: widget.onFilterTap == null ? 10.0 : 60.0,
          ),
          enabled: !ref.watch(trackingProvider) && trackLocation != null,
          icon: Icons.my_location,
          tooltip: loc.mapLocate,
          onPressed: () {
            ref.read(geolocationProvider.notifier).enableTracking(context);
          },
          onLongPressed: () {
            if (ref.read(rotationProvider) != 0.0) {
              ref.read(rotationProvider.notifier).state = 0.0;
              mapController.rotate(0.0);
            } else {
              ref.read(geolocationProvider.notifier).enableTracking(context);
            }
          },
        ),
        if (widget.drawZoomButtons)
          ZoomButtonsOptions(
            alignment: leftHand ? Alignment.bottomLeft : Alignment.bottomRight,
            padding: EdgeInsets.symmetric(
              horizontal: 0.0,
              // colorsFromLegend is an indirect way to know it's micromapping mode.
              vertical:
                  !leftHand && amenities.isEmpty && widget.colorsFromLegend
                      ? 80.0
                      : 20.0,
            ),
          ),
      ],
      nonRotatedChildren: [
        if (showAttribution && imagery.attribution != null)
          buildAttributionWidget(imagery),
      ],
      children: [
        TileLayerWidget(
          options: buildTileLayerOptions(imagery),
        ),
        LocationMarkerWidget(),
        if (trackLocation != null)
          CircleLayerWidget(
            options: CircleLayerOptions(
              circles: [
                for (final objLocation in widget.otherObjects)
                  CircleMarker(
                    point: objLocation,
                    color: Colors.black.withOpacity(0.4),
                    radius: 2.0,
                  ),
              ],
            ),
          ),
        MarkerLayerWidget(
          options: MarkerLayerOptions(
            markers: [
              if (!ref.watch(trackingProvider) || trackLocation == null)
                Marker(
                  rotate: true,
                  rotateOrigin: Offset(0.0, -5.0),
                  rotateAlignment: Alignment.bottomCenter,
                  point:
                      mapCenter, // mapController.center throws late init exception
                  anchorPos: AnchorPos.exactly(Anchor(15.0, 5.0)),
                  builder: (ctx) => Icon(Icons.location_pin),
                ),
              for (var i = amenities.length - 1; i >= 0; i--)
                Marker(
                  anchorPos: AnchorPos.align(AnchorAlign.top),
                  point: amenities[i].location,
                  rotate: true,
                  builder: (ctx) => Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        child: ClipPath(
                          clipper: MarkerClipper(),
                          child: Container(
                              decoration: getMarkerDecoration(amenities[i], legendCon)
                          )
                        ),
                        /*decoration: BoxDecoration(
                          color: getIconColor(amenities[i], legendCon)
                              .withOpacity(widget.drawNumbers ? 0.7 : 1.0),
                          borderRadius: BorderRadius.circular(iconSize / 4),
                        ),*/
                        width: iconSize,
                        height: iconSize * 1.5,
                      ),
                      /*if (!widget.drawNumbers && amenities[i].isIncomplete)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(iconSize / 6),
                          ),
                          width: iconSize / 3,
                          height: iconSize / 3,
                        ),*/
                      if (widget.drawNumbers && i < 9)
                        Container(
                          padding: EdgeInsets.only(left: 1.0),
                          child: Icon(
                            getIconFromAmenityType(amenities[i]),
                            size: iconSize / 1.5,
                          ),
                          /*Text(
                            (i + 1).toString(),
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: iconSize - 6.0,
                            ),
                          ),*/
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
