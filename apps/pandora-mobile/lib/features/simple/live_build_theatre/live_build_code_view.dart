import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../pandora_v2_ui.dart';
import 'live_build_reducer.dart';

class LiveBuildCodeView extends StatefulWidget {
  const LiveBuildCodeView({
    super.key,
    required this.state,
    this.onFollowChanged,
  });

  final LiveBuildTheatreState state;
  final ValueChanged<bool>? onFollowChanged;

  @override
  State<LiveBuildCodeView> createState() => _LiveBuildCodeViewState();
}

class _LiveBuildCodeViewState extends State<LiveBuildCodeView> {
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  bool _followLive = true;

  @override
  void didUpdateWidget(covariant LiveBuildCodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_followLive &&
        widget.state.visibleCode.length != oldWidget.state.visibleCode.length &&
        widget.state.hasVisibleRealSource) {
      _scrollToLive();
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  void _scrollToLive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_verticalController.hasClients) return;
      _verticalController.jumpTo(_verticalController.position.maxScrollExtent);
    });
  }

  void _pauseFollow() {
    if (!_followLive) return;
    setState(() => _followLive = false);
    widget.onFollowChanged?.call(false);
  }

  void _resumeFollow() {
    if (!_followLive) {
      setState(() => _followLive = true);
      widget.onFollowChanged?.call(true);
    }
    _scrollToLive();
  }

  @override
  Widget build(BuildContext context) {
    // Hard invariant: no source bytes means no code surface at all.
    if (!widget.state.hasVisibleRealSource) {
      return const SizedBox.shrink();
    }

    final file = widget.state.activeFile ?? 'Source';
    final height = (MediaQuery.sizeOf(context).height * .32)
        .clamp(180.0, 300.0)
        .toDouble();

    return Semantics(
      label: 'Live source. Writing $file',
      liveRegion: true,
      child: Container(
        key: const Key('live-build-code-surface'),
        decoration: BoxDecoration(
          color: PandoraV2Colors.surface,
          border: Border.all(color: PandoraV2Colors.line),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      file,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PandoraV2Colors.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _languageLabel(file),
                    style: const TextStyle(
                      color: PandoraV2Colors.muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: const Color(0xFF111318),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.metrics.axis == Axis.vertical &&
                              notification is UserScrollNotification &&
                              notification.direction != ScrollDirection.idle) {
                            _pauseFollow();
                          }
                          return false;
                        },
                        child: SingleChildScrollView(
                          key: const Key('live-build-code-scroll'),
                          controller: _verticalController,
                          padding: const EdgeInsets.all(14),
                          child: SingleChildScrollView(
                            controller: _horizontalController,
                            scrollDirection: Axis.horizontal,
                            child: Text(
                              widget.state.visibleCode,
                              softWrap: false,
                              style: const TextStyle(
                                color: Color(0xFFF5F7FA),
                                fontFamily: 'monospace',
                                fontSize: 12.5,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!_followLive)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: FilledButton.tonalIcon(
                        key: const Key('live-build-return-to-live'),
                        onPressed: _resumeFollow,
                        icon: const Icon(
                          Icons.arrow_downward_rounded,
                          size: 16,
                        ),
                        label: const Text('Return to live'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _languageLabel(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return 'SOURCE';
  final extension = path.substring(dot + 1).toLowerCase();
  switch (extension) {
    case 'dart':
      return 'DART';
    case 'ts':
    case 'tsx':
      return 'TS';
    case 'js':
    case 'jsx':
      return 'JS';
    case 'json':
      return 'JSON';
    case 'sql':
      return 'SQL';
    case 'html':
      return 'HTML';
    case 'css':
      return 'CSS';
    default:
      return extension.toUpperCase();
  }
}
