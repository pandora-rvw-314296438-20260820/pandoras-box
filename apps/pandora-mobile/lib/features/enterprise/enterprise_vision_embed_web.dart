// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

const String _viewType = 'pandora-world-port-cams-cape-marina';
const String _embedUrl =
    'https://worldportcams.com/embed/usa/florida/cape-marina-live-webcam-hd-stream-canaveral-fl';

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
          'World Port Cams live camera — Cape Marina, Canaveral',
        );
        return iframe;
      },
    );
    _registered = true;
  }

  return HtmlElementView(viewType: _viewType);
}
