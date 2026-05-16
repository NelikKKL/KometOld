import 'package:flutter/material.dart';

class KometColoredSegment {
  final String text;
  final Color? color;

  KometColoredSegment(this.text, this.color);
}

// omm — новый тип сегмента для 3D-моделей OMM
enum KometSegmentType { normal, colored, galaxy, pulse, omm }

class KometSegment {
  final String text;
  final KometSegmentType type;
  final Color? color;

  KometSegment(this.text, this.type, {this.color});
}
