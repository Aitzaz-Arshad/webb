// lib/widgets/camera_stream_web.dart
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

Widget createWebCameraStream(String url, double width, double height) {
  // Use a unique viewType for each URL to avoid collisions when opening/closing
  final String viewType = 'camera-stream-${url.hashCode}';
  
  // Register the view factory
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final imageElement = html.ImageElement()
      ..src = url
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';
    return imageElement;
  });

  return SizedBox(
    width: width,
    height: height,
    child: HtmlElementView(viewType: viewType),
  );
}
