import 'package:flutter/material.dart';

Widget buildEnterpriseVisionEmbed() => Container(
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
            'Live public camera preview is available in Pandora Enterprise Web.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Authorized enterprise cameras can use the native Vision Intelligence ingest path.',
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
