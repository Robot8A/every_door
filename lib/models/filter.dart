import 'amenity.dart';
import 'floor.dart';
import 'diets.dart';
import 'address.dart';

class PoiFilter {
  /*static const nullFloor = Floor(floor: 'null', level: 0.123456);
  static const nullAddress = StreetAddress(housenumber: 'null', street: 'null');*/
  static const nullDiet = Diet(diet: 'null', friendly: 'null');

  /*final Floor? floor;
  final StreetAddress? address;*/
  final Diet? diet;
  final bool includeNoData; // TODO: what does this even mean
  final bool notChecked;

  PoiFilter(
      {this.diet,
      this.includeNoData = true,
      this.notChecked = false});

  PoiFilter copyWith(
      {Diet? diet,
      bool? includeNoData,
      bool? notChecked}) {
    return PoiFilter(
      diet: diet == nullDiet ? null : diet ?? this.diet,
      includeNoData: includeNoData ?? this.includeNoData,
      notChecked: notChecked ?? this.notChecked,
    );
  }

  bool get isEmpty => diet == null && !notChecked;
  bool get isNotEmpty => diet != null || notChecked;

  bool matches(OsmChange amenity) {
    if (notChecked && !amenity.isOld) return false;
    final tags = amenity.getFullTags();
    final diets = MultiDiet.fromTags(tags);
    bool matchesDiet = diet == null ||
        ((diet?.isEmpty ?? true)
            ? diets.isEmpty
            : diets.diets.contains(diet));
    return matchesDiet;
  }

  @override
  String toString() => 'PoiFilter(diet: $diet)';
}
