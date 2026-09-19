// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

const String _viewType = 'pandora-world-port-cams-key-largo';
const String _embedUrl =
    'https://worldportcams.com/embed/usa/florida/courtyard-key-largo';

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
        iframe.setAttribute('loading', 'lazy');
        iframe.setAttribute(
          'title',
          'World Port Cams live camera — Courtyard Key Largo',
        );
        return iframe;
      },
    );
    _registered = true;
  }

  return HtmlElementView(viewType: _viewType);
}
