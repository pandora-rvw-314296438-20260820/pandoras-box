
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

const String _androidVisionViewType = 'pandora/camstreamer_kabukicho';

Widget buildEnterpriseVisionEmbed() {
  if (Platform.isAndroid) {
    return const AndroidView(
      viewType: _androidVisionViewType,
      layoutDirection: TextDirection.ltr,
    );
  }
  return Container(
    color: const Color(0xFF111111),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(24),
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.videocam_outlined,
          size: 42,
          color: Colors.white70,
        ),
        SizedBox(height: 12),
        Text(
          'Live public camera preview is available in Pandora Enterprise Web and Android.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Authorized enterprise cameras can use the governed Vision Intelligence ingest path.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white60,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}
