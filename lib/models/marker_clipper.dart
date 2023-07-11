import 'dart:core';

import 'package:flutter/material.dart';

class MarkerClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    double width = size.width;
    double height = size.height;

    final path = Path()
      ..lineTo(0, height*2/3)
      ..lineTo(width/2, height)
      ..lineTo(width, height*2/3)
      ..lineTo(width, 0)
      ..lineTo(0, 0);
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => true;
}
