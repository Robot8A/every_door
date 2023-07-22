import 'amenity.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class Diet implements Comparable<Diet> {
  final String? diet;
  final String? friendly;
  final bool duplicate;

  const Diet({this.diet, this.friendly, this.duplicate = false});

  static const empty = Diet(diet:null, friendly: null);

  Diet makeDuplicate() => Diet(diet: diet, friendly: friendly, duplicate: true);

  bool get isEmpty => diet == null && friendly == null;
  bool get isNotEmpty => !isEmpty;
  bool get isComplete => diet != null && friendly != null;

  @override
  bool operator ==(Object other) =>
      other is Diet && diet == other.diet && friendly == other.friendly;

  @override
  int get hashCode => (diet ?? '').hashCode + (friendly ?? '').hashCode;

  @override
  String toString() {
    return '$diet $friendly';
  }

  String get string {
    if (isEmpty) return '';
    return '${diet ?? ""}/${friendly ?? ""}';
  }

  @override
  int compareTo(Diet other) {
    var dComp = diet!.compareTo(other.diet!);
    var fComp = friendly!.compareTo(other.friendly!);

    if (dComp == fComp) return dComp;
    return dComp;
  }

  /// Removes incomplete duplicates.
  static collapse(Set<Diet> diets) {
    final compDiets = diets
        .where((element) => element.isComplete)
        .map((e) => e.diet!)
        .toSet();
    final compFriendlies = diets
        .where((element) => element.isComplete)
        .map((e) => e.friendly!)
        .toSet();

    // Remove incomplete diets where a complete alternative exists.
    diets.removeWhere((d) {
      if (!d.isComplete) {
        if (d.diet != null && compDiets.contains(d.diet))
          return true;
        if (d.friendly != null && compFriendlies.contains(d.diet))
          return true;
      }
      return false;
    });

    // Complete diets can contain duplicates on diets or friendlies.
    // TODO: replace these floors with .makeDuplicate()
  }

  static collapseList(List<Diet> diets) {
    final set = diets.toSet();
    collapse(set);
    final result = set.toList();
    result.sort();
    return result;
  }
}


class MultiDiet {
  List<Diet> diets;

  MultiDiet(this.diets);

  bool get isEmpty => diets.isEmpty;
  bool get isNotEmpty => diets.isNotEmpty;
  List<String> get strings => diets.map((f) => f.string).toList();

  factory MultiDiet.fromTags(Map<String, String> tags) {
    List<String?> dietParts = [];
    for (var key in tags.keys) {
      var keySplit = key.split(":");
      if (keySplit.length == 2 && keySplit[0] == "diet") {
        dietParts.add(keySplit[1]);
      }
    }

    final List<String?> friendlyParts = [];
    for (var key in dietParts)
      friendlyParts.add(tags[key]);

    if (dietParts.isEmpty) return MultiDiet([]);

    return MultiDiet(Iterable.generate(
      dietParts.length,
      (i) => Diet(
        diet: i >= dietParts.length ? null : dietParts[i],
        friendly: i >= friendlyParts.length ? null : friendlyParts[i],
      ),
    ).where((element) => element.isNotEmpty).toList());
  }

  static final _kTailSemicolons = RegExp(r';+$');

  setTags(OsmChange element) {
    /*if (diets.isEmpty) {
      element.removeTag('level');
      element.removeTag('addr:floor');
    } else {
      floors.sort();
      element['level'] = floors
          .map((f) => f._levelStr)
          .join(';')
          .replaceFirst(_kTailSemicolons, '');
      element['addr:floor'] = floors
          .map((f) => f.floor ?? '')
          .join(';')
          .replaceFirst(_kTailSemicolons, '');
    }*/
  }
}
