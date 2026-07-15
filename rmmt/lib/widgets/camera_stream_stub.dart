// lib/widgets/camera_stream_stub.dart
import 'package:flutter/material.dart';

Widget createWebCameraStream(String url, double width, double height) {
  return Image.network(
    url,
    fit: BoxFit.cover,
    loadingBuilder: (context, child, loadingProgress) {
      if (loadingProgress == null) return child;
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF2FE0C6), strokeWidth: 2),
      );
    },
    errorBuilder: (context, error, stackTrace) {
      return const Center(
        child: Icon(Icons.videocam_off, color: Colors.white24, size: 48),
      );
    },
  );
}
