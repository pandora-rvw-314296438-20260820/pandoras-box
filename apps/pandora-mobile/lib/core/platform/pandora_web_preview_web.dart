// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'pandora_preview_contract.dart';

const int _maxFileCount = 1000;
const int _maxFileBytes = 10 * 1024 * 1024;
const int _maxBundleBytes = 12 * 1024 * 1024;

class PandoraWebPreview extends StatefulWidget {
  const PandoraWebPreview({
    super.key,
    required this.files,
    required this.versionId,
    required this.fallback,
    this.selectionEnabled = false,
    this.selectedSelector,
    this.onSelection,
  });

  final List<Map<String, Object?>> files;
  final String versionId;
  final Widget fallback;
  final bool selectionEnabled;
  final String? selectedSelector;
  final ValueChanged<PandoraPreviewSelection?> onSelection;

  static bool get isSupported => true;

  @override
  State<PandoraWebPreview> createState() => _PandoraWebPreviewState();
}

class _PandoraWebPreviewState extends State<PandoraWebPreview> {
  static int _nextViewId = 0;

  late final String _viewType;
  html.IFrameElement? _frame;
  html.MessagePort? _port;
  StreamSubscription<html.Event>? _loadSubscription;
  StreamSubscription<html.MessageEvent>? _portSubscription;
  Map<String, _PreviewFile>? _bundle;
  String? _srcdoc;

  @override
  void initState() {
    super.initState();
    _viewType = 'pandora-exact-preview-web-${_nextViewId++}';
    _materialize();
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _createFrame(),
    );
  }

  @override
  void didUpdateWidget(covariant PandoraWebPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bundleChanged = oldWidget.versionId != widget.versionId ||
        !identical(oldWidget.files, widget.files);
    if (bundleChanged) {
      _materialize();
      _reloadFrame();
      return;
    }
    if (oldWidget.selectionEnabled != widget.selectionEnabled ||
        oldWidget.selectedSelector != widget.selectedSelector) {
      _sendState();
    }
  }

  @override
  void dispose() {
    _loadSubscription?.cancel();
    _portSubscription?.cancel();
    _port?.close();
    _loadSubscription = null;
    _portSubscription = null;
    _port = null;
    _frame = null;
    super.dispose();
  }

  void _materialize() {
    final versionId = widget.versionId.trim();
    final parsed = _parseBundle(widget.files);
    if (versionId.isEmpty || parsed == null) {
      _bundle = null;
      _srcdoc = null;
      return;
    }
    _bundle = parsed;
    _srcdoc = _buildSrcdoc(parsed, versionId);
  }

  html.IFrameElement _createFrame() {
    final frame = html.IFrameElement()
      ..setAttribute('sandbox', 'allow-scripts')
      ..setAttribute('referrerpolicy', 'no-referrer')
      ..setAttribute('aria-label', 'Pandora exact preview')
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block';
    _frame = frame;
    _loadSubscription?.cancel();
    _loadSubscription = frame.onLoad.listen((_) => _attachPort());
    frame.srcdoc = _srcdoc ?? _unavailableDocument;
    return frame;
  }

  void _reloadFrame() {
    final frame = _frame;
    if (frame == null) return;
    _portSubscription?.cancel();
    _port?.close();
    _portSubscription = null;
    _port = null;
    frame.srcdoc = _srcdoc ?? _unavailableDocument;
  }

  void _attachPort() {
    final frame = _frame;
    final target = frame?.contentWindow;
    final versionId = widget.versionId.trim();
    if (frame == null ||
        target == null ||
        _bundle == null ||
        versionId.isEmpty) {
      return;
    }

    _portSubscription?.cancel();
    _port?.close();

    final channel = html.MessageChannel();
    _port = channel.port1;
    _portSubscription = channel.portÄ¹½¹5•ÍÍ…”¹±¥ÍÑ•¸¡}¡…¹‘±•A½ÉÑ5•ÍÍ…”¤ì(€€€Ñ…É•Ğ¹Á½ÍÑ5•ÍÍ…” (€€€€€€ñMÑÉ¥¹œ°=‰©•Ğüùì(€€€€€€€€ÑåÁ”œè€Á…¹‘½É„µÁÉ•Ù¥•Üµ¥¹¥Ğœ°(€€€€€€€€Ù•ÉÍ¥½¹%œèÙ•ÉÍ¥½¹%°(€€€€€ô°(€€€€€€œ¨œ°(€€€€€€ñ¡Ñµ°¹5•ÍÍ…•A½ÉĞùm¡…¹¹•°¹Á½ÉĞÉt°(€€€€¤ì(€ô((€Ù½¥}¡…¹‘±•A½ÉÑ5•ÍÍ…”¡¡Ñµ°¹5•ÍÍ…•Ù•¹Ğ•Ù•¹Ğ¤ì(€€€™¥¹…°É…Ü€ô•Ù•¹Ğ¹‘…Ñ„ì(€€€¥˜€¡É…Ü¥Ì„MÑÉ¥¹œñğ€…µ½Õ¹Ñ•¤É•ÑÕÉ¸ì(€€€=‰©•Ğü‘•½‘•ì(€€€ÑÉäì(€€€€€‘•½‘•€ô©Í½¹•½‘”¡É…Ü¤ì(€€€ô…Ñ €¡|¤ì(€€€€€É•ÑÕÉ¸ì(€€€ô(€€€¥˜€¡‘•½‘•¥Ì„5…À¤É•ÑÕÉ¸ì((€€€MÑÉ¥¹œÙ…±Õ”¡MÑÉ¥¹œ­•ä¤€ôø€¡‘•½‘•‘m­•åt…ÌMÑÉ¥¹œü€üü€œœ¤¹ÑÉ¥´ ¤ì(€€€¥˜€¡Ù…±Õ” Ù•ÉÍ¥½¹%œ¤€„ôİ¥‘•Ğ¹Ù•ÉÍ¥½¹%¹ÑÉ¥´ ¤¤É•ÑÕÉ¸ì(€€€™¥¹…°ÑåÁ”€ôÙ…±Õ” ÑåÁ”œ¤ì(€€€¥˜€¡ÑåÁ”€ôô€É•…‘äœ¤ì(€€€€€}Í•¹‘MÑ…Ñ” ¤ì(€€€€€É•ÑÕÉ¸ì(€€€ô(€€€¥˜€¡ÑåÁ”€„ô€Í•±•Ñ¥½¸œ¤É•ÑÕÉ¸ì((€€€‘½Õ‰±”¹Õµ‰•È¡MÑÉ¥¹œ­•ä¤€ôø€¡‘•½‘•‘m­•åt…Ì¹Õ´ü¤ü¹Ñ½½Õ‰±” ¤€üü€Àì(€€€¥¹Ğü¥¹Ñ••È¡MÑÉ¥¹œ­•ä¤€ôø€¡‘•½‘•‘m­•åt…Ì¹Õ´ü¤ü¹Ñ½%¹Ğ ¤ì(€€€™¥¹…°İ¥‘Ñ €ô¹Õµ‰•È İ¥‘Ñ œ¤ì(€€€™¥¹…°¡•¥¡Ğ€ô¹Õµ‰•È ¡•¥¡Ğœ¤ì(€€€™¥¹…°Í•±•Ñ¥½¸€ôA…¹‘½É…AÉ•Ù¥•İM•±•Ñ¥½¸ (€€€€€Ñ…œèÙ…±Õ” Ñ…œœ¤°(€€€€€Í•±•Ñ½ÈèÙ…±Õ” Í•±•Ñ½Èœ¤°(€€€€€Ñ•áĞèÙ…±Õ” Ñ•áĞœ¤°(€€€€€Í•µ…¹Ñ¥%èÙ…±Õ” Í•µ…¹Ñ¥%œ¤°(€€€€€É½±”èÙ…±Õ” É½±”œ¤°(€€€€€…•ÍÍ¥‰±•9…µ”èÙ…±Õ” …•ÍÍ¥‰±•9…µ”œ¤°(€€€€€É½ÕÑ”èÙ…±Õ” É½ÕÑ”œ¤¹¥ÍµÁÑä€ü€œ¼œ€èÙ…±Õ” É½ÕÑ”œ¤°(€€€€€Í½ÕÉ•¥±”è(€€€€€€€€€Ù…±Õ” Í½ÕÉ•¥±”œ¤¹¥ÍµÁÑä€ü€¥¹‘•à¹¡Ñµ°œ€èÙ…±Õ” Í½ÕÉ•¥±”œ¤°(€€€€€Í½ÕÉ•1¥¹”è¥¹Ñ••È Í½ÕÉ•1¥¹”œ¤°(€€€€€‰½Õ¹‘Ìèİ¥‘Ñ €ø€À€˜˜¡•¥¡Ğ€ø€À(€€€€€€€€€€üA…¹‘½É…AÉ•Ù¥•İ	½Õ¹‘Ì (€€€€€€€€€€€€€àè¹Õµ‰•È àœ¤°(€€€€€€€€€€€€€äè¹Õµ‰•È äœ¤°(€€€€€€€€€€€€€İ¥‘Ñ èİ¥‘Ñ °(€€€€€€€€€€€€€¡•¥¡Ğè¡•¥¡Ğ°(€€€€€€€€€€€€¤(€€€€€€€€€€è¹Õ±°°(€€€€¤ì(€€€¥˜€¡Í•±•Ñ¥½¸¹Í•±•Ñ½È¹¥ÍµÁÑä€˜˜Í•±•Ñ¥½¸¹Ñ…œ¹¥ÍµÁÑä¤É•ÑÕÉ¸ì(€€€İ¥‘•Ğ¹½¹M•±•Ñ¥½¸ü¹…±°¡Í•±•Ñ¥½¸¤ì(€ô((€Ù½¥}Í•¹‘MÑ…Ñ” ¤ì(€€€™¥¹…°Á½ÉĞ€ô}Á½ÉĞì(€€€¥˜€¡Á½ÉĞ€ôô¹Õ±°¤É•ÑÕÉ¸ì(€€€Á½ÉĞ¹Á½ÍÑ5•ÍÍ…” (€€€€€©Í½¹¹½‘” ñMÑÉ¥¹œ°=‰©•Ğüùì(€€€€€€€€ÑåÁ”œè€ÍÑ…Ñ”œ°(€€€€€€€€Ù•ÉÍ¥½¹%œèİ¥‘•Ğ¹Ù•ÉÍ¥½¹%¹ÑÉ¥´ ¤°(€€€€€€€€Í•±•Ñ¥½¹¹…‰±•œèİ¥‘•Ğ¹Í•±•Ñ¥½¹¹…‰±•°(€€€€€€€€Í•±•Ñ•‘M•±•Ñ½Èœèİ¥‘•Ğ¹Í•±•Ñ•‘M•±•Ñ½Èü¹ÑÉ¥´ ¤€üü€œœ°(€€€€€ô¤°(€€€€¤ì(€ô((€½Ù•ÉÉ¥‘”(€]¥‘•Ğ‰Õ¥±¡	Õ¥±‘½¹Ñ•áĞ½¹Ñ•áĞ¤ì(€€€¥˜€¡}‰Õ¹‘±”€ôô¹Õ±°ñğ}ÍÉ‘½Œ€ôô¹Õ±°¤É•ÑÕÉ¸İ¥‘•Ğ¹™…±±‰…¬ì(€€€É•ÑÕÉ¸!Ñµ±±•µ•¹ÑY¥•Ü¡Ù¥•İQåÁ”è}Ù¥•İQåÁ”¤ì(€ô)ô()±…ÍÌ}AÉ•Ù¥•İ¥±”ì(€½¹ÍĞ}AÉ•Ù¥•İ¥±”¡ì(€€€É•ÅÕ¥É•Ñ¡¥Ì¹Á…Ñ °(€€€É•ÅÕ¥É•Ñ¡¥Ì¹µ¥µ•QåÁ”°(€€€É•ÅÕ¥É•Ñ¡¥Ì¹‘…Ñ…	…Í”ØĞ°(€€€É•ÅÕ¥É•Ñ¡¥Ì¹‰åÑ•Ì°(€ô¤ì((€™¥¹…°MÑÉ¥¹œÁ…Ñ ì(€™¥¹…°MÑÉ¥¹œµ¥µ•QåÁ”ì(€™¥¹…°MÑÉ¥¹œ‘…Ñ…	…Í”ØĞì(€™¥¹…°1¥ÍĞñ¥¹Ğø‰åÑ•Ìì)ô()5…ÀñMÑÉ¥¹œ°}AÉ•Ù¥•İ¥±”øü}Á…ÉÍ•	Õ¹‘±”¡1¥ÍĞñ5…ÀñMÑÉ¥¹œ°=‰©•ĞüøøÉ…İ¥±•Ì¤ì(€¥˜€¡É…İ¥±•Ì¹¥ÍµÁÑäñğÉ…İ¥±•Ì¹±•¹Ñ €ø}µ…á¥±•½Õ¹Ğ¤É•ÑÕÉ¸¹Õ±°ì(€™¥¹…°™¥±•Ì€ô€ñMÑÉ¥¹œ°}AÉ•Ù¥•İ¥±”ùíôì(€Ù…ÈÑ½Ñ…±	åÑ•Ì€ô€Àì(€ÑÉäì(€€€™½È€¡™¥¹…°É…Ü¥¸É…İ¥±•Ì¤ì(€€€€€™¥¹…°Á…Ñ €ô€¡É…İl™¥±”t…ÌMÑÉ¥¹œü€üü€œœ¤¹ÑÉ¥´ ¤ì(€€€€€™¥¹…°µ¥µ•QåÁ”€ô€¡É…İlµ¥µ•QåÁ”t…ÌMÑÉ¥¹œü€üü€œœ¤¹ÑÉ¥´ ¤ì(€€€€€™¥¹…°‘…Ñ…	…Í”ØĞ€ô€¡É…İl‘…Ñ…	…Í”ØĞt…ÌMÑÉ¥¹œü€üü€œœ¤¹ÑÉ¥´ ¤ì(€€€€€¥˜€ …}¥ÍM…™•A…Ñ ¡Á…Ñ ¤ñğ(€€€€€€€€€µ¥µ•QåÁ”¹¥ÍµÁÑäñğ(€€€€€€€€€‘…Ñ…	…Í”ØĞ¹¥ÍµÁÑäñğ(€€€€€€€€€™¥±•Ì¹½¹Ñ…¥¹Í-•ä¡Á…Ñ ¤¤ì(€€€€€€€É•ÑÕÉ¸¹Õ±°ì(€€€€€ô(€€€€€™¥¹…°‰åÑ•Ì€ô‰…Í”ØÑ•½‘”¡‘…Ñ…	…Í”ØĞ¤ì(€€€€€¥˜€¡‰åÑ•Ì¹±•¹Ñ €ø}µ…á¥±•	åÑ•Ì¤É•ÑÕÉ¸¹Õ±°ì(€€€€€Ñ½Ñ…±	åÑ•Ì€¬ô‰åÑ•Ì¹±•¹Ñ ì(€€€€€¥˜€¡Ñ½Ñ…±	åÑ•Ì€ø}µ…á	Õ¹‘±•	åÑ•Ì¤É•ÑÕÉ¸¹Õ±°ì(€€€€€™¥±•ÍmÁ…Ñ¡t€ô}AÉ•Ù¥•İ¥±” (€€€€€€€Á…Ñ èÁ…Ñ °(€€€€€€€µ¥µ•QåÁ”èµ¥µ•QåÁ”°(€€€€€€€‘…Ñ…	…Í”ØĞè‘…Ñ…	…Í”ØĞ°(€€€€€€€‰åÑ•Ìè‰åÑ•Ì°(€€€€€€¤ì(€€€ô(€ô…Ñ €¡|¤ì(€€€É•ÑÕÉ¸¹Õ±°ì(€ô(€É•ÑÕÉ¸™¥±•Ì¹½¹Ñ…¥¹Í-•ä ¥¹‘•à¹¡Ñµ°œ¤€ü™¥±•Ì€è¹Õ±°ì)ô()‰½½°}¥ÍM…™•A…Ñ ¡MÑÉ¥¹œÁ…Ñ ¤ì(€¥˜€¡Á…Ñ ¹¥ÍµÁÑäñğ(€€€€€Á…Ñ ¹±•¹Ñ €ø€ÔÄÈñğ(€€€€€Á…Ñ ¹ÍÑ…ÉÑÍ]¥Ñ  œ¼œ¤ñğ(€€€€€Á…Ñ ¹•¹‘Í]¥Ñ  œ¼œ¤ñğ(€€€€€Á…Ñ ¹½¹Ñ…¥¹Ì¡Èpœ¤ñğ(€€€€€Á…Ñ ¹½¹Ñ…¥¹Ì qÔÀÀÀÀœ¤ñğ(€€€€€Á…Ñ ¹½¹Ñ…¥¹Ì œüœ¤ñğ(€€€€€Á…Ñ ¹½¹Ñ…¥¹Ì œŒœ¤¤ì(€€€É•ÑÕÉ¸™…±Í”ì(€ô(€É•ÑÕÉ¸Á…Ñ ¹ÍÁ±¥Ğ œ¼œ¤¹•Ù•Éä (€€€€€€€€¡Á…ÉĞ¤€ôø(€€€€€€€€€€€Á…ÉĞ¹¥Í9=ÑµÁÑä€˜˜(€€€€€€€€€€€Á…ÉĞ€„ô€œ¸œ€˜˜(€€€€€€€€€€€Á…ÉĞ€„ô€œ¸¸œ€˜˜(€€€€€€€€€€€Á…ÉĞ¹±•¹Ñ €ğô€ÈÔÔ°(€€€€€€¤ì)ô()MÑÉ¥¹œ}‰Õ¥±‘MÉ‘½Œ¡5…ÀñMÑÉ¥¹œ°}AÉ•Ù¥•İ¥±”ø™¥±•Ì°MÑÉ¥¹œÙ•ÉÍ¥½¹%¤ì(€™¥¹…°¥¹‘•à€ô™¥±•Íl¥¹‘•à¹¡Ñµ°t„ì(€™¥¹…°¡Ñµ±Q•áĞ€ôÕÑ˜à¹‘•½‘”¡¥¹‘•à¹‰åÑ•Ì°…±±½İ5…±™½Éµ•è™…±Í”¤ì(€™¥¹…°…¡”€ô€ñMÑÉ¥¹œ°MÑÉ¥¹œùíôì(€™¥¹…°É•İÉ¥ÑÑ•¸€ô}É•İÉ¥Ñ•!Ñµ°¡¡Ñµ±Q•áĞ°™¥±•Ì°…¡”°€¥¹‘•à¹¡Ñµ°œ¤ì(€™¥¹…°‰½½ÑÍÑÉ…À€ô}‰½½ÑÍÑÉ…ÁMÉ¥ÁĞ¡Ù•ÉÍ¥½¹%¤ì(€½¹ÍĞÍÀ€ô€‰‘•™…Õ±ĞµÍÉŒ€¹½¹”œì€ˆ(€€€€€€‰ÍÉ¥ÁĞµÍÉŒ€Õ¹Í…™”µ¥¹±¥¹”œ‘…Ñ„è‰±½ˆèì€ˆ(€€€€€€‰ÍÑå±”µÍÉŒ€Õ¹Í…™”µ¥¹±¥¹”œ‘…Ñ„è‰±½ˆèì€ˆ(€€€€€€‰¥µœµÍÉŒ‘…Ñ„è‰±½ˆèì€ˆ(€€€€€€‰™½¹ĞµÍÉŒ‘…Ñ„è‰±½ˆèì€ˆ(€€€€€€‰µ•‘¥„µÍÉŒ‘…Ñ„è‰±½ˆèì€ˆ(€€€€€€‰½¹¹•ĞµÍÉŒ€¹½¹”œì€ˆ(€€€€€€‰™É…µ”µÍÉŒ€¹½¹”œì€ˆ(€€€€€€‰¡¥±µÍÉŒ€¹½¹”œì€ˆ(€€€€€€‰İ½É­•ÈµÍÉŒ€¹½¹”œì€ˆ(€€€€€€‰½‰©•ĞµÍÉŒ€¹½¹”œì€ˆ(€€€€€€‰™½É´µ…Ñ¥½¸€¹½¹”œì€ˆ(€€€€€€‰‰…Í”µÕÉ¤€¹½¹”œì€ˆ(€€€€€€‰¹…Ù¥…Ñ”µÑ¼€¹½¹”œˆì((€™¥¹…°Í•ÕÉ¥Ñå!•…€ô(€€€€€€œñµ•Ñ„¡ÑÑÀµ•ÅÕ¥Øô‰½¹Ñ•¹ĞµM•ÕÉ¥ÑäµA½±¥äˆ½¹Ñ•¹Ğôˆ‘í¡Ñµ±Í…Á”¹½¹Ù•ÉĞ¡ÍÀ¥ôˆøœ(€€€€€€œñµ•Ñ„¹…µ”ô‰É•™•ÉÉ•Èˆ½¹Ñ•¹Ğô‰¹¼µÉ•™•ÉÉ•Èˆøœ(€€€€€€œñÍÉ¥ÁĞø‘‰½½ÑÍÑÉ…Àğ½ÍÉ¥ÁĞøœì((€™¥¹…°İ¥Ñ¡½ÕÑ	…Í”€ôÉ•İÉ¥ÑÑ•¸¹É•Á±…•±° (€€€I•áÀ¡Èœñ‰…Í•q‰mxùt¨øœ°…Í•M•¹Í¥Ñ¥Ù”è™…±Í”¤°(€€€€œœ°(€€¤ì(€™¥¹…°¡•…€ôI•áÀ¡Èœñ¡•…‘qmb[^>]*>', caseSensitive: false);
  final match = head.firstMatch(withoutBase);
  if (match != null) {
    return withoutBase.replaceRange(match.end, match.end, securityHead);
  }
  final htmlTag = RegExp(r'<html[^>]*>', caseSensitive: false);
  final htmlMatch = htmlTag.firstMatch(withoutBase);
  if (htmlMatch != null) {
    return withoutBase.replaceRange(
      htmlMatch.end,
      htmlMatch.end,
      '<head>$securityHead</head>',
    );
  }
  return '<!doctype html><html><head>$securityHead</head><body>$withoutBase</body></html>';
}

String _rewriteHtml(
  String source,
  Map<String, _PreviewFile> files,
  Map<String, String> cache,
  String basePath,
) {
  var output = source.replaceAllMapped(
    RegExp(r'''(\b(?:src|href|poster)\s*=\s*["'])([^"']+)(["'])''',
        caseSensitive: false),
    (match) {
      final ref = match.group(2)!;
      final path = _resolvePath(basePath, ref, files);
      if (path == null) return match.group(0)!;
      return '${match.group(1)}${_materializeUri(path, files, cache, <String>{})}${match.group(3)}';
    },
  );
  output = output.replaceAllMapped(
    RegExp(r'''url\(\s*(["']?)([^)"']+)\1\s*\)''', caseSensitive: false),
    (match) {
      final ref = match.group(2)!;
      final path = _resolvePath(basePath, ref, files);
      if (path == null) return match.group(0)!;
      return 'url("${_materializeUri(path, files, cache, <String>{})}")';
    },
  );
  return output;
}

String _materializeUri(
  String path,
  Map<String, _PreviewFile> files,
  Map<String, String> cache,
  Set<String> visiting,
) {
  final cached = cache[path];
  if (cached != null) return cached;
  final file = files[path];
  if (file == null) return '';
  if (!visiting.add(path)) return _rawDataUri(file);

  var bytes = file.bytes;
  final mime = file.mimeType.toLowerCase();
  if (mime.contains('css') ||
      mime.contains('javascript') ||
      mime.endsWith('/json') ||
      mime.startsWith('text/')) {
    try {
      var text = utf8.decode(bytes, allowMalformed: false);
      if (mime.contains('css')) {
        text = text.replaceAllMapped(
          RegExp(r'''url\(\s*(["']?([^)"']+)\1\s*\)''', caseSensitive: false),
          (match) {
            final nested = _resolvePath(path, match.group(2)!, files);
            if (nested == null) return match.group(0)!;
            return 'url("${_materializeUri(nested, files, cache, visiting)}")';
          },
        );
      } else if (mime.contains(&javascript')) {
        text = _rewriteModuleSpecifiers(text, path, files, cache, visiting);
      }
      bytes = utf8.encode(text);
    } catch (_) {
      visiting.remove(path);
      return _rawDataUri(file);
    }
  }

  final uri = 'data:${file.mimeType};base64,${base64Encode(bytes)}';
  cache[path] = uri;
  visiting.remove(path);
  return uri;
}

String _rewriteModuleSpecifiers(
  String source,
  String basePath,
  Map<String, _PreviewFile> files,
  Map<String, String> cache,
  Set<String> visiting,
) {
  var output = source.replaceAllMapped(
    RegExp(r'''(\bfrom\s*["'])[^"']+(["'])'''),
    (match) {
      final nested = _resolvePath(basePath, match.group(2)!, files);
      if (nested == null) return match.group(0)!;
      return '${match.group(1)}${_materializeUri(nested, files, cache, visiting)}${match.group(3)}';
    },
  );
  output = output.replaceAllMapped(
    RegExp(r'''(\bimport\s*["'])[^"']+)(["'])'''),
    (match) {
      final nested = _resolvePath(basePath, match.group(2)!, files);
      if (nested == null) return match.group(0)!;
      return '${match.group(1)}${_materializeUri(nested, files, cache, visiting)}${match.group(3)}';
    },
  );
  output = output.replaceAllMapped(
    RegExp(r'''(\bimport\s*\(\s*["'])([^"']+)(["']\s*\))'''),
    (match) {
      final nested = _resolvePath(basePath, match.group(2)!, files);
      if (nested == null) return match.group(0)!;
      return '${match.group(1)}${_materializeUri(nested, files, cache, visiting)}${match.group(3)}';
    },
  );
  return output;
}

String? _resolvePath(
  String basePath,
  String rawRef,
  Map<String, _PreviewFile> files,
) {
  final ref = rawRef.trim();
  if (ref.isEmpty ||
      ref.startsWith('#') ||
      ref.startsWith('data:') ||
      ref.startsWith('blob:') ||
      ref.startsWith('javascript:') ||
      ref.startsWith('mailto:') ||
      ref.startsWith('tel:') ||
      ref.startsWith('//') ||
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+\.-]*:').hasMatch(ref)) {
    return null;
  }
  final clean = ref.split('#').first.split('?').first;
  if (clean.isEmpty) return null;
  final parts = <String>[];
  if (!clean.startsWith('/')) {
    final base = basePath.split('/');
    if (base.isNOtEmpty) base.removeLast();
    parts.addAll(base);
  }
  for (final segment in clean.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isEmpty) return null;
      parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  final path = parts.join('/');
  return files.containsKey(path) ? path : null;
}

String _rawDataUri(_PreviewFile file) =>
    'data:$zvf–ÆRæÖ–ÖUG—WÓ¶&6ScBÂG¶f–ÆRæFF&6ScGÒs° ¥7G&–ærö&ö÷G7G&67&—B…7G&–ærfW'6–öä–B’°¢f–æÂVæ6öFVEfW'6–öâÒ§6öäVæ6öFR‡fW'6–öä–B“°¢&WGW&ârrp¢‚‚’Óâ°¢wW6R7G&–7Bs°¢6öç7BW‡V7FVEfW'6–öä–BÒFVæ6öFVEfW'6–öã°¢ÆWB&—f–ÆVvVE÷'BÒçVÆÃ°¢ÆWB6VÆV7F–öäVæ&ÆVBÒfÇ6S°¢ÆWB6VÆV7FVE6VÆV7F÷"Òrs° ¢6öç7BW66U6VÆV7F÷"ÒfÇVRÓà¢‡v–æF÷rä552bb552æW66R¢ò552æW66R‡fÇVR¢¢7G&–ær‡fÇVR’ç&WÆ6R‚õµæ×¤Õ£Ó•òÕÒörÂ6‚ÓâuÅÅÅÂr²6‚“° ¢6öç7B6ÆV%6VÆV7F–öâÒ‚’Óâ°¢Fö7VÖVçBçVW'•6VÆV7F÷$ÆÂ‚u¶FF×æF÷&×&Wf–Wr×6VÆV7FVCÒ'G'VR%Òr¢æf÷$V6‚†æöFRÓâæöFRç&VÖ÷fTGG&–'WFR‚vFF×æF÷&×&Wf–Wr×6VÆV7FVBr’“°¢Ó° ¢6öç7BVç7W&U6VÆV7F–öå7G–ÆRÒ‚’Óâ°¢–b†Fö7VÖVçBævWDVÆVÖVçD'”–B‚wæF÷&×&Wf–Wr×6VÆV7F–öâ×7G–ÆRr’’&WGW&ã°¢6öç7B7G–ÆRÒFö7VÖVçBæ7&VFTVÆVÖVçB‚w7G–ÆRr“°¢7G–ÆRæ–BÒwæF÷&×&Wf–Wr×6VÆV7F–öâ×7G–ÆRs°¢7G–ÆRçFW‡D6öçFVçBĞ¢u¶FF×æF÷&×&Wf–Wr×6VÆV7FVCÒ'G'VR%×¶÷WFÆ–æS£'‚6öÆ–B&v&ƒ#RÃ#RÃ#RÂãs"’×÷'FçC¶÷WFÆ–æRÖöfg6WC£'‚–×÷'FçGÒs°¢Fö7VÖVçBæ†VBæVæD6†–ÆB‡7G–ÆR“°¢Ó° ¢6öç7BÇ•6VÆV7FVE6VÆV7F÷"Ò‚’Óâ°¢6ÆV%6VÆV7F–öâ‚“°¢–b‚6VÆV7FVE6VÆV7F÷"’&WGW&ã°¢G'’°¢6öç7BæöFRÒFö7VÖVçBçVW'•6VÆV7F÷"‡6VÆV7FVE6VÆV7F÷"“°¢–b†æöFR’°¢Vç7W&U6VÆV7F–öå7G–ÆR‚“°¢æöFRç6WDGG&–'WFR‚vFF×æF÷&×&Wf–Wr×6VÆV7FVBrÂwG'VRr“°¢Ğ¢Ò6F6‚…ò’·Ğ¢Ó° ¢6öç7B6VÆV7F÷$f÷"ÒæöFRÓâ°¢6öç7B6VÖçF–4–BÒæöFRævWDGG&–'WFR‚vFF×æF÷&Ö–Br“°¢–b‡6VÖçF–4–B’&WGW&âu¶FF×æF÷&Ö–CÒ"r²W66U6VÆV7F÷"‡6VÖçF–4–B’²r%Òs°¢–b†æöFRæ–B’&WGW&âr2r²W66U6VÆV7F÷"†æöFRæ–B“°¢6öç7B'G2ÒµÓ°¢ÆWB7W'&VçBÒæöFS°¢v†–ÆR†7W'&VçBbb7W'&VçBææöFUG—RÓÓÒbb7W'&VçBÓÒFö7VÖVçBæFö7VÖVçDVÆVÖVçB’°¢ÆWB'BÒ7W'&VçBçFtæÖRçFôÆ÷vW$66R‚“°¢6öç7B÷væW"Ò7W'&VçBç&VçDVÆVÖVçC°¢–b†÷væW"’°¢6öç7BVW'2Ò'&’æg&öÒ†÷væW"æ6†–ÆG&Vâ¢æf–ÇFW"†6†–ÆBÓâ6†–ÆBçFtæÖRÓÓÒ7W'&VçBçFtæÖR“°¢–b‡VW'2æÆVæwF‚â’°¢'B³Òs¦çF‚Ööb×G—R‚r²‡VW'2æ–æFW„öb†7W'&VçB’²’²r’s°¢Ğ¢Ğ¢'G2çVç6†–gB‡'B“°¢7W'&VçBÒ÷væW#°¢–b‡'G2æÆVæwF‚ãÒ‚’'&V³°¢Ğ¢&WGW&â'G2æ¦ö–â‚râr“°¢Ó° ¢v–æF÷ræFDWfVçDÆ—7FVæW"‚vÖW76vRrÂ†WfVçB’Óâ°¢–b‚WfVçBæ—5G'W7FVBÇÂWfVçBç÷'G2æÆVæwF‚ÓÒ’&WGW&ã°¢6öç7BÖW76vRÒWfVçBæFF°¢–b‚ÖW76vRÇÀ¢ÖW76vRçG—RÓÒwæF÷&×&Wf–WrÖ–æ—BrÇÀ¢ÖW76vRçfW'6–öä–BÓÒW‡V7FVEfW'6–öä–BÇÀ¢&—f–ÆVvVE÷'BÓÒçVÆÂ’°¢&WGW&ã°¢Ğ¢WfVçBç7F÷–ÖÖVF–FU&÷vF–öâ‚“°¢6öç7B÷'BÒWfVçBç÷'G5³Ó°¢&—f–ÆVvVE÷'BÒ÷'C°¢÷'BæöæÖW76vRÒ÷'DWfVçBÓâ°¢–b‡G—Vöb÷'DWfVçBæFFÓÒw7G&–ærr’&WGW&ã°¢ÆWB6öÖÖæC°¢G'’²6öÖÖæBÒ¥4ôâç'6R‡÷'DWfVçBæFF“²Ò6F6‚…ò’²&WGW&ã²Ğ¢–b‚6öÖÖæBÇÂ6öÖÖæBçfW'6–öä–BÓÒW‡V7FVEfW'6–öä–BÇÂ6öÖÖæBçG—RÓÒw7FFRr’&WGW&ã°¢6VÆV7F–öäVæ&ÆVBÒ6öÖÖæBç6VÆV7F–öäVæ&ÆVBÓÓÒG'VS°¢6VÆV7FVE6VÆV7F÷"ÒG—Vöb6öÖÖæBç6VÆV7FVE6VÆV7F÷"ÓÓÒw7G&–ærp¢ò6öÖÖæBç6VÆV7FVE6VÆV7F÷ ¢¢rs°¢Ç•6VÆV7FVE6VÆV7F÷"‚“°¢Ó°¢÷'Bç÷7DÖW76vR„¥4ôâç7G&–æv–g’‡°¢G—S¢w&VG’rÀ¢fW'6–öä–C¢W‡V7FVEfW'6–öä–@¢Ò’“°¢ÒÂG'VR“° ¢Fö7VÖVçBæFDWfVçDÆ—7FVæW"‚v6Æ–6²rÂ†WfVçB’Óâ°¢6öç7Bæ6†÷"ÒWfVçBçF&vWBbbWfVçBçF&vWBæ6Æ÷6W7@¢òWfVçBçF&vWBæ6Æ÷6W7B‚v¶‡&VeÒr¢¢çVÆÃ°¢–b†æ6†÷"’°¢6öç7B‡&VbÒ7G&–ær†æ6†÷"ævWDGG&–'WFR‚v‡&Vbr’ÇÂrr’çG&–Ò‚“°¢–b‚õâƒó¥¶×¤Õ¥Õ¶×¤Õ£Ó’²âÕÒ£§ÅÅÂõÅÂò’òçFW7B†‡&Vb’b`¢‡&Vbç7F'G5v—F‚‚vFF¢r’b`¢‡&Vbç7F'G5v—F‚‚v&Æö#¢r’’°¢WfVçBç&WfVçDFVfVÇB‚“°¢WfVçBç7F÷–ÖÖVF–FU&÷vF–öâ‚“°¢&WGW&ã°¢Ğ¢Ğ ¢–b‚6VÆV7F–öäVæ&ÆVBÇÂ&—f–ÆVvVE÷'B’&WGW&ã°¢6öç7BVÆVÖVçBÒFö7VÖVçBæVÆVÖVçDg&öÕö–çB†WfVçBæ6Æ–VçE‚ÂWfVçBæ6Æ–VçE’“°¢–b‚VÆVÖVçBÇÂVÆVÖVçBÓÓÒFö7VÖVçBæFö7VÖVçDVÆVÖVçBÇÂVÆVÖVçBÓÓÒFö7VÖVçBæ&öG’’&WGW&ã° ¢WfVçBç&WfVçDFVfVÇB‚“°¢WfVçBç7F÷–ÖÖVF–FU&÷vF–öâ‚“°¢6ÆV%6VÆV7F–öâ‚“°¢Vç7W&U6VÆV7F–öå7G–ÆR‚“°¢VÆVÖVçBç6WDGG&–'WFR‚vFF×æF÷&×&Wf–Wr×6VÆV7FVBrÂwG'VRr“°¢6VÆV7FVE6VÆV7F÷"Ò6VÆV7F÷$f÷"†VÆVÖVçB“° ¢6öç7B&V7BÒVÆVÖVçBævWD&÷VæF–æt6Æ–VçE&V7B‚“°¢6öç7BÆ–æU&rÒVÆVÖVçBævWDGG&–'WFR‚vFF×æF÷&×6÷W&6RÖÆ–æRr“°¢6öç7B6÷W&6TÆ–æRÒÆ–æU&rbbõåÅÆBµÂBòçFW7B†Æ–æU&r’òçVÖ&W"†Æ–æU&r’¢çVÆÃ°¢6öç7B†6…&÷WFRÒÆö6F–öâæ†6‚bbÆö6F–öâæ†6‚ç7F'G5v—F‚‚r2òr¢òÆö6F–öâæ†6‚ç7V'7G&–ærƒ¢¢rs° ¢&—f–ÆVvVE÷'Bç÷7DÖW76vR„¥4ôâç7G&–æv–g’‡°¢G—S¢w6VÆV7F–öârÀ¢fW'6–öä–C¢W‡V7FVEfW'6–öä–BÀ¢Fs¢VÆVÖVçBçFtæÖRòVÆVÖVçBçFtæÖRçFôÆ÷vW$66R‚’¢rrÀ¢6VÆV7F÷#¢6VÆV7FVE6VÆV7F÷"À¢FW‡C¢7G&–ær†VÆVÖVçBçFW‡D6öçFVçBÇÂrr’çG&–Ò‚’ç6Æ–6RƒÂS’À¢6VÖçF–4–C¢7G&–ær†VÆVÖVçBævWDGG&–'WFR‚vFF×æF÷&Ö–Br’ÇÂrr’À¢&öÆS¢7G&–ær†VÆVÖVçBævWDGG&–'WFR‚w&öÆRr’ÇÂrr’À¢66W76–&ÆTæÖS¢7G&–ær€¢VÆVÖVçBævWDGG&–'WFR‚v&–ÖÆ&VÂr’ÇÀ¢VÆVÖVçBævWDGG&–'WFR‚wF—FÆRr’ÇÀ¢rp¢’À¢&÷WFS¢†6…&÷WFRÇÂròrÀ¢6÷W&6Tf–ÆS¢7G&–ær€¢VÆVÖVçBævWDGG&–'WFR‚vFF×æF÷&×6÷W&6RÖf–ÆRr’ÇÂv–æFW‚æ‡FÖÂp¢’À¢6÷W&6TÆ–æRÀ¢ƒ¢&V7Bç‚À¢“¢&V7Bç’À¢v–GFƒ¢&V7Bçv–GF‚À¢†V–v‡C¢&V7Bæ†V–v‡@¢Ò’“°¢ÒÂG'VR“°§Ò’‚“°¢rrs°§Ğ ¦6öç7B7G&–ær÷Væf–Æ&ÆTFö7VÖVçBÒsÂFö7G—R‡FÖÃãÆ‡FÖÃãÆ†VCâp¢sÆÖWF‡GGÖWV—cÒ$6öçFVçBÕ6V7W&—G’ÕöÆ–7’"p¢v6öçFVçCÒ&FVfVÇB×7&2b33“¶æöæRb33“³²6öææV7B×7&2b33“¶æöæRb33“³²p¢vg&ÖR×7&2b33“¶æöæRb33“³²f÷&ÒÖ7F–öâb33“¶æöæRb33“²#âp¢sÂö†VCãÆ&öG“ãÂö&öG“ãÂö‡FÖÃâs° 