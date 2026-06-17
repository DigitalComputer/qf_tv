import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_win_floating/webview_plugin.dart' show WindowsPlatformWebViewController;
import 'package:webview_win_floating/webview_win_floating.dart' show WinNavigationDelegate;

import '../models/models.dart';

/// Zone C media — parity with qf_screen ZoneC (image/video/youtube/iframe/logo).
///
/// Linux: [webview_win_floating] is a native GTK overlay — defer load until
/// WebViewWidget has Zone C bounds (two post-frame passes) so queue UI stays visible.
class TvMediaContent extends StatefulWidget {
  const TvMediaContent({super.key, required this.item});

  final TvMediaItem item;

  @override
  State<TvMediaContent> createState() => _TvMediaContentState();
}

class _TvMediaContentState extends State<TvMediaContent> {
  static const _embedOrigin = 'https://queueflow.local';

  VideoPlayerController? _videoCtrl;
  WebViewController? _webCtrl;
  bool _videoFailed = false;
  bool _webFailed = false;
  bool _webReady = false;

  @override
  void initState() {
    super.initState();
    // Defer init until Zone C has layout bounds (webview_win_floating native overlay).
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void didUpdateWidget(covariant TvMediaContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id || oldWidget.item.url != widget.item.url) {
      _disposePlayers();
      _videoFailed = false;
      _webFailed = false;
      _webReady = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    }
  }

  Future<void> _init() async {
    if (!mounted) return;
    final url = widget.item.url;
    if (url == null || url.isEmpty) return;

    switch (widget.item.kind) {
      case 'video':
        await _initVideo(url);
      case 'youtube':
        await _initYouTubeWebView(url);
      case 'iframe':
        await _initIframeWebView(url);
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
      await ctrl.setVolume(1);
      await ctrl.play();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('qf_tv video_player failed: $e');
      await ctrl.dispose();
      _videoCtrl = null;
      _videoFailed = true;
      await _loadGenericWebView(_videoHtmlDataUrl(url));
      if (mounted) setState(() {});
    }
  }

  Future<void> _initYouTubeWebView(String url) async {
    final id = _youtubeId(url);
    final html = '''
<!DOCTYPE html><html><head>
<meta charset="utf-8">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}
iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
</head><body>
<iframe
  src="https://www.youtube-nocookie.com/embed/$id?autoplay=1&mute=1&loop=1&playlist=$id&controls=0&playsinline=1&rel=0"
  referrerpolicy="strict-origin-when-cross-origin"
  allow="autoplay; encrypted-media; fullscreen"
></iframe>
</body></html>''';
    await _loadHtmlWebView(html);
  }

  Future<void> _initIframeWebView(String url) async {
    final safe = url.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
    final html = '''
<!DOCTYPE html><html><head>
<meta charset="utf-8">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}
iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
</head><body>
<iframe src="$safe" referrerpolicy="strict-origin-when-cross-origin"
  sandbox="allow-scripts allow-same-origin allow-presentation"
  allow="autoplay; encrypted-media; fullscreen"></iframe>
</body></html>''';
    await _loadHtmlWebView(html);
  }

  Future<void> _loadGenericWebView(String loadUrl) async {
    await _prepareWebView();
    _scheduleWebLoad(() {
      _webCtrl!.loadRequest(Uri.parse(loadUrl));
    });
  }

  Future<void> _loadHtmlWebView(String html) async {
    await _prepareWebView();
    _scheduleWebLoad(() {
      _webCtrl!.loadHtmlString(html, baseUrl: _embedOrigin);
    });
  }

  /// Mount [WebViewWidget] first so layout bounds reach native overlay, then load.
  Future<void> _prepareWebView() async {
    if (_webCtrl != null) return;
    final ctrl = _createWebController();
    _webCtrl = ctrl;
    await _hideLinuxWebView(ctrl);
    if (mounted) setState(() => _webReady = true);
  }

  void _scheduleWebLoad(void Function() load) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _webCtrl == null) return;
        load();
      });
    });
  }

  WebViewController _createWebController() {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);

    if (Platform.isLinux) {
      final platform = ctrl.platform;
      if (platform is WindowsPlatformWebViewController) {
        platform.controller.setNavigationDelegate(
          WinNavigationDelegate(
            onFullScreenChanged: (isFullScreen) {
              if (isFullScreen) platform.controller.setFullScreen(false);
            },
            onWebResourceError: (_) {
              if (mounted) setState(() => _webFailed = true);
            },
          ),
        );
      }
    }

    return ctrl;
  }

  Future<void> _hideLinuxWebView(WebViewController ctrl) async {
    if (!Platform.isLinux) return;
    final platform = ctrl.platform;
    if (platform is WindowsPlatformWebViewController) {
      await platform.controller.setVisibility(false);
    }
  }

  void _disposePlayers() {
    _videoCtrl?.dispose();
    _videoCtrl = null;
    if (_webCtrl != null && Platform.isLinux) {
      final platform = _webCtrl!.platform;
      if (platform is WindowsPlatformWebViewController) {
        platform.controller.setVisibility(false);
      }
    }
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
        if (_webFailed) return _mediaFallback(item);
        if (_webCtrl != null && _webReady) {
          return WebViewWidget(controller: _webCtrl!);
        }
        return _mediaFallback(item);
      case 'youtube':
      case 'iframe':
        if (_webFailed) return _mediaFallback(item);
        if (_webCtrl != null && _webReady) {
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

  Widget _mediaFallback(TvMediaItem item) {
    final url = item.url;
    if (item.kind == 'youtube' && url != null && url.isNotEmpty) {
      final thumb = _youtubeThumbnail(url);
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            thumb,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                item.title ?? 'Vídeo indisponível',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 20),
              ),
            ),
          ),
        ],
      );
    }
    return Center(
      child: Text(
        item.title ?? item.kind.toUpperCase(),
        style: const TextStyle(color: Colors.white38, fontSize: 24),
      ),
    );
  }

  static String _youtubeId(String url) {
    return RegExp(r'(?:v=|youtu\.be/)([^&?/]+)').firstMatch(url)?.group(1) ?? url;
  }

  static String _youtubeThumbnail(String url) {
    return 'https://img.youtube.com/vi/${_youtubeId(url)}/hqdefault.jpg';
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
