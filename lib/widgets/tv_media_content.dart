import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/models.dart';

/// Zone C media — parity with qf_screen ZoneC (image/video/youtube/iframe/logo).
class TvMediaContent extends StatefulWidget {
  const TvMediaContent({super.key, required this.item});

  final TvMediaItem item;

  @override
  State<TvMediaContent> createState() => _TvMediaContentState();
}

class _TvMediaContentState extends State<TvMediaContent> {
  VideoPlayerController? _videoCtrl;
  WebViewController? _webCtrl;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant TvMediaContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id || oldWidget.item.url != widget.item.url) {
      _disposePlayers();
      _videoFailed = false;
      _init();
    }
  }

  Future<void> _init() async {
    final url = widget.item.url;
    if (url == null || url.isEmpty) return;

    switch (widget.item.kind) {
      case 'video':
        await _initVideo(url);
      case 'youtube':
        _initWebView(_youtubeEmbedUrl(url));
      case 'iframe':
        _initWebView(url);
      default:
        break;
    }
  }

  Future<void> _initVideo(String url) async {
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoCtrl = ctrl;
    try {
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setVolume(0);
      await ctrl.play();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('qf_tv video_player failed, webview fallback: $e');
      await ctrl.dispose();
      _videoCtrl = null;
      _videoFailed = true;
      _initWebView(_videoHtmlDataUrl(url));
      if (mounted) setState(() {});
    }
  }

  void _initWebView(String loadUrl) {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadRequest(Uri.parse(loadUrl));
    _webCtrl = ctrl;
    if (mounted) setState(() {});
  }

  void _disposePlayers() {
    _videoCtrl?.dispose();
    _videoCtrl = null;
    _webCtrl = null;
  }

  @override
  void dispose() {
    _disposePlayers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final url = item.url;
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    switch (item.kind) {
      case 'image':
        return Image.network(
          url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      case 'logo':
        return ColoredBox(
          color: Colors.white,
          child: Center(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        );
      case 'video':
        if (!_videoFailed && _videoCtrl != null && _videoCtrl!.value.isInitialized) {
          return ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoCtrl!.value.size.width,
                height: _videoCtrl!.value.size.height,
                child: VideoPlayer(_videoCtrl!),
              ),
            ),
          );
        }
        if (_webCtrl != null) {
          return WebViewWidget(controller: _webCtrl!);
        }
        return const ColoredBox(color: Colors.black);
      case 'youtube':
      case 'iframe':
        if (_webCtrl != null) {
          return WebViewWidget(controller: _webCtrl!);
        }
        return const ColoredBox(color: Colors.black);
      default:
        return Center(
          child: Text(
            item.title ?? item.kind.toUpperCase(),
            style: const TextStyle(color: Colors.white38, fontSize: 24),
          ),
        );
    }
  }

  static String _youtubeEmbedUrl(String url) {
    final id = RegExp(r'(?:v=|youtu\.be/)([^&?/]+)').firstMatch(url)?.group(1) ?? url;
    return 'https://www.youtube.com/embed/$id'
        '?autoplay=1&mute=1&loop=1&playlist=$id&controls=0&rel=0';
  }

  /// HLS / direct video fallback via WebKit (same approach as qf_screen Hls.js).
  static String _videoHtmlDataUrl(String url) {
    final safe = url.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
    final isHls = url.contains('.m3u8');
    final html = isHls
        ? '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>html,body{margin:0;height:100%;background:#000}video{width:100%;height:100%;object-fit:cover}</style>
<script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.7"></script></head><body>
<video id="v" autoplay muted loop playsinline></video>
<script>
const v=document.getElementById('v'),u="$safe";
if(Hls.isSupported()){const h=new Hls();h.loadSource(u);h.attachMedia(v);}
else if(v.canPlayType('application/vnd.apple.mpegurl'))v.src=u;
</script></body></html>'''
        : '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>html,body{margin:0;height:100%;background:#000}video{width:100%;height:100%;object-fit:cover}</style></head><body>
<video src="$safe" autoplay muted loop playsinline></video></body></html>''';
    return 'data:text/html;charset=utf-8,${Uri.encodeComponent(html)}';
  }
}
