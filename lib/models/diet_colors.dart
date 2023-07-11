import 'package:flutter/material.dart';

class DietColorsGenerator {
  static const Map colors = {
    "diet:halal": {
      "only": Color(0xFF008000),
      "yes": Color(0xFF00C200)
    },
    "diet:kosher": {
      "only": Color(0xFF006FA7),
      "yes": Color(0xFF00BEFA)
    },
    "diet:vegan": {
      "only": Color(0xFFA73448),
      "yes": Color(0xFFFE8391)
    },
    "diet:vegetarian": {
      "only": Color(0xFF7449A9),
      "yes": Color(0xFFC095FC)
    },
    "diet:gluten_free": {
      "only": Color(0xFF885900),
      "yes": Color(0xFFD8A616)
    }
  };

  // Return a list of colors corresponding to the passed diets
  static List<Color> getColors(Map diets) {
    List<Color> colorList = List.empty(growable: true);

    for (var entry in diets.entries) {
      try {
        var c = colors[entry.key][entry.value];
        colorList.add(c);
      } catch (_) {}
    }

    return colorList;
  }
}