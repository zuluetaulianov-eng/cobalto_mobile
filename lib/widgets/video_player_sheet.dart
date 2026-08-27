import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// Determina si una URL de video es de YouTube.
bool _isYouTubeUrl(String url) {
  return url.contains('youtube.com') ||
      url.contains('youtu.be') ||
      url.contains('youtube-nocookie.com');
}

/// Determina si una URL es de un servicio externo embebido (Vimeo, Rumble, etc.)
bool _isEmbedUrl(String url) {
  return url.contains('vimeo.com') ||
      url.contains('rumble.com') ||
      url.contains('dailymotion.com') ||
      url.contains('facebook.com/video') ||
      url.contains('twitch.tv');
}

/// ──────────────────────────────────────────────────────────────────────────
/// Sheet táctica para reproducción de video de noticias COBALTO.
/// Soporta:
///   • YouTube  → YoutubePlayer (sin iframe, nativo)
///   • MP4/HLS  → VideoPlayer + Chewie (controles completos)
///   • Embeds   → Redirige a URL externa
/// ──────────────────────────────────────────────────────────────────────────
class VideoPlayerSheet extends StatefulWidget {
  final String videoUrl;
  final String title;

  const VideoPlayerSheet({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  static Future<void> show(
    BuildContext context, {
    required String videoUrl,
    required String title,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => VideoPlayerSheet(videoUrl: videoUrl, title: title),
    );
  }

  @override
  State<VideoPlayerSheet> createState() => _VideoPlayerSheetState();
}

class _VideoPlayerSheetState extends State<VideoPlayerSheet> {
  // Reproductores
  VideoPlayerController? _vpController;
  ChewieController? _chewieController;
  YoutubePlayerController? _ytController;

  bool _isYT = false;
  bool _isEmbed = false;
  bool _isLoading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final url = widget.videoUrl;

    if (_isYouTubeUrl(url)) {
      final videoId = YoutubePlayer.convertUrlToId(url);
      if (videoId == null) {
        setState(() {
          _errorMsg = 'No se pudo extraer el ID de YouTube.';
          _isLoading = false;
        });
        return;
      }
      _ytController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          enableCaption: false,
          useHybridComposition: true,
        ),
      );
      setState(() {
        _isYT = true;
        _isLoading = false;
      });
    } else if (_isEmbedUrl(url)) {
      setState(() {
        _isEmbed = true;
        _isLoading = false;
      });
    } else {
      // MP4 / HLS / WebM / MOV
      try {
        _vpController = VideoPlayerController.networkUrl(Uri.parse(url));
        await _vpController!.initialize();
        _chewieController = ChewieController(
          videoPlayerController: _vpController!,
          autoPlay: true,
          looping: false,
          allowFullScreen: true,
          allowMuting: true,
          showControls: true,
          materialProgressColors: ChewieProgressColors(
            playedColor: const Color(0xFF00E5FF),
            handleColor: const Color(0xFF00FFAA),
            backgroundColor: Colors.white12,
            bufferedColor: const Color(0xFF00E5FF).withOpacity(0.3),
          ),
          placeholder: Container(color: Colors.black),
          errorBuilder: (ctx, err) => _buildError(err),
        );
        if (mounted) setState(() => _isLoading = false);
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMsg = 'Error al cargar el video: $e';
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _vpController?.dispose();
    _ytController?.dispose();
    // Restaurar orientación al cerrar
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Widget _buildError(String? msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF2D55), size: 48),
          const SizedBox(height: 12),
          Text(
            msg ?? 'No se pudo reproducir el video.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF00E5FF), strokeWidth: 2),
            SizedBox(height: 12),
            Text(
              'CARGANDO VIDEO...',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMsg != null) return _buildError(_errorMsg);

    if (_isEmbed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.open_in_browser, color: Color(0xFF00E5FF), size: 56),
              const SizedBox(height: 16),
              const Text(
                'CONTENIDO EXTERNO',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Este video está alojado en una plataforma externa.\nÁbrelo en el navegador para verlo.',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('ABRIR EN NAVEGADOR'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    }

    if (_isYT && _ytController != null) {
      return YoutubePlayerBuilder(
        player: YoutubePlayer(
          controller: _ytController!,
          showVideoProgressIndicator: true,
          progressIndicatorColor: const Color(0xFF00E5FF),
          progressColors: const ProgressBarColors(
            playedColor: Color(0xFF00E5FF),
            handleColor: Color(0xFF00FFAA),
            bufferedColor: Colors.white24,
            backgroundColor: Colors.black38,
          ),
        ),
        builder: (context, player) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [player],
        ),
      );
    }

    if (_chewieController != null) {
      return Chewie(controller: _chewieController!);
    }

    return _buildError(null);
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF0A0B10),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // ── Drag handle ──────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── Header táctico ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2D55).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFFF2D55).withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam, color: Color(0xFFFF2D55), size: 14),
                      SizedBox(width: 4),
                      Text(
                        'INTEL VIDEO',
                        style: TextStyle(
                          color: Color(0xFFFF2D55),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // ── Player ───────────────────────────────────────────────
          Expanded(
            child: Container(
              color: Colors.black,
              child: _buildPlayer(),
            ),
          ),

          // ── Footer táctico ───────────────────────────────────────
          if (!_isLoading && _errorMsg == null && !_isEmbed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF0F121C),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFF00E5FF), size: 14),
                  const SizedBox(width: 6),
                  const Text(
                    'COBALTO INTEL VIDEO',
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 9,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _isYT ? 'YouTube' : 'Streaming Directo',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
