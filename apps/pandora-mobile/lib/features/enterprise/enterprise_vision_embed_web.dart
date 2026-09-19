// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

const String _viewType = 'pandora-shibuya-ai-vision-live-cam';
const String _embedUrl =
    'https://www.youtube.com/embed/live_stream?channel=UCfvMaqBPqsHXSbmmKzpDvow&autoplay=1&mute=1&playsinline=1&rel=0';

bool _registered = false;

Widget buildEnterpriseVisionEmbed() {
  if (!_registered) {
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..src = _embedUrl
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '100%';
        iframe.setAttribute(
          'allow',
          'autoplay; fullscreen; picture-in-picture',
        );
        iframe.setAttribute('allowfullscreen', 'true');
        iframe.setAttribute(
          'referrerpolicy',
          'strict-origin-when-cross-origin',
        );
        iframe.setAttribute('loading', 'lazy');
        iframe.setAttribute(
          'title',
          'Shibuya Ai Vision Miyamasuzaka live camera',
        );
        return iframe;
      },
    );
    _registered = true;
  }

  return HtmlElementView(viewType: _viewType);
}
