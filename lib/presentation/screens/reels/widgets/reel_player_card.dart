import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/navigation/route_observer.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/reel_item.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/presentation/screens/signs/signs_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:video_player/video_player.dart';

class ReelPlayerCard extends ConsumerStatefulWidget {
  final ReelItem reel;
  final bool isActive;
  final bool isMuted;
  final bool isLiked;
  final bool isSaved;
  final int sharesCount;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleSave;
  final VoidCallback onShare;

  const ReelPlayerCard({
    super.key,
    required this.reel,
    required this.isActive,
    required this.isMuted,
    required this.isLiked,
    required this.isSaved,
    required this.sharesCount,
    required this.onToggleMute,
    required this.onToggleLike,
    required this.onToggleSave,
    required this.onShare,
  });

  @override
  ConsumerState<ReelPlayerCard> createState() => _ReelPlayerCardState();
}

class _ReelPlayerCardState extends ConsumerState<ReelPlayerCard>
    with SingleTickerProviderStateMixin, RouteAware {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showPlayPauseIcon = false;
  bool _showHeartBurst = false;
  Timer? _iconHideTimer;
  bool _routeSubscribed = false;

  // Перемотка (Scrubbing)
  bool _isScrubbing = false;
  double _scrubProgress = 0.0;
  bool _wasPlayingBeforeScrub = false;
  DateTime _lastSeekTime = DateTime.now();

  late AnimationController _heartAnimController;
  late Animation<double> _heartScaleAnimation;
  late Animation<double> _heartOpacityAnimation;

  static const List<Shadow> _subtleShadows = [
    Shadow(
      offset: Offset(0, 1),
      blurRadius: 2,
      color: Color(0x44000000),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _heartScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.4)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.4, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_heartAnimController);

    _heartOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 70),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_heartAnimController);

    _initPlayer();
  }

  void _initPlayer() {
    final videoPath = widget.reel.videoUrl;
    if (videoPath.startsWith('assets/')) {
      _controller = VideoPlayerController.asset(videoPath);
    } else if (videoPath.startsWith('http://') ||
        videoPath.startsWith('https://')) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoPath));
    } else {
      _controller = VideoPlayerController.file(File(videoPath));
    }

    _controller!
      ..setLooping(true)
      ..setVolume(widget.isMuted ? 0.0 : 1.0)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _isInitialized = true;
        });
        if (widget.isActive) {
          _controller?.play();
          setState(() {
            _isPlaying = true;
          });
        }
      }).catchError((error) {
        debugPrint('Error loading reel video (${widget.reel.id}): $error');
      });

    _controller?.addListener(_playerListener);
  }

  void _playerListener() {
    if (!mounted || _controller == null) return;
    final isPlaying = _controller!.value.isPlaying;
    if (!_isScrubbing && isPlaying != _isPlaying) {
      setState(() {
        _isPlaying = isPlaying;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ReelPlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.reel.videoUrl != widget.reel.videoUrl) {
      _controller?.removeListener(_playerListener);
      _controller?.dispose();
      _isInitialized = false;
      _initPlayer();
      return;
    }

    if (oldWidget.isMuted != widget.isMuted) {
      _controller?.setVolume(widget.isMuted ? 0.0 : 1.0);
    }

    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        if (_isInitialized) {
          _controller?.play();
          setState(() => _isPlaying = true);
        }
      } else {
        _controller?.pause();
        setState(() => _isPlaying = false);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_routeSubscribed) {
      final route = ModalRoute.of(context);
      if (route is PageRoute) {
        appRouteObserver.subscribe(this, route);
        _routeSubscribed = true;
      }
    }
  }

  @override
  void didPushNext() {
    // Новый экран открыт поверх видео (тренировка, знаки и т.д.) — останавливаем видео
    if (_controller != null && _isInitialized) {
      _controller!.pause();
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    }
  }

  @override
  void didPopNext() {
    // Вернулись обратно на экран видео
    if (widget.isActive && _controller != null && _isInitialized) {
      _controller!.play();
      if (mounted) {
        setState(() => _isPlaying = true);
      }
    }
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    _iconHideTimer?.cancel();
    _heartAnimController.dispose();
    _controller?.removeListener(_playerListener);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized || _isScrubbing) return;
    HapticFeedbackHelper.tap();
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    setState(() {
      _showPlayPauseIcon = true;
    });
    _iconHideTimer?.cancel();
    _iconHideTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() => _showPlayPauseIcon = false);
      }
    });
  }

  void _handleDoubleTap() {
    HapticFeedbackHelper.select();
    if (!widget.isLiked) {
      widget.onToggleLike();
    }
    setState(() {
      _showHeartBurst = true;
    });
    _heartAnimController.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() => _showHeartBurst = false);
      }
    });
  }

  void _openDeepLink() async {
    HapticFeedbackHelper.tap();
    if (_controller != null && _isInitialized) {
      _controller!.pause();
      setState(() => _isPlaying = false);
    }

    // 1. Если это знаки — открываем группу знаков
    if (widget.reel.targetType == 'signs' ||
        widget.reel.targetSignCategory != null) {
      final categoryName =
          widget.reel.targetSignCategory ?? 'Запрещающие знаки';
      final allSigns = await ref.read(signsProvider.future);
      final catSigns = (allSigns[categoryName] as Map<String, dynamic>?) ??
          (allSigns.entries.firstWhere(
            (e) => e.key.toLowerCase().contains(categoryName.toLowerCase()),
            orElse: () => allSigns.entries.first,
          ).value as Map<String, dynamic>);

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SignCategoryScreen(
            categoryName: categoryName,
            signs: catSigns,
          ),
        ),
      );
      if (mounted && widget.isActive && _controller != null && _isInitialized) {
        _controller!.play();
        setState(() => _isPlaying = true);
      }
      return;
    }

    // 2. Если это билет — открываем тренировку с нужным вопросом
    if (widget.reel.targetType == 'ticket' &&
        widget.reel.targetTicket != null) {
      final ticketNumber = widget.reel.targetTicket!;
      final questionIndex = (widget.reel.targetQuestion ?? 1) - 1;

      final tickets = await ref.read(ticketsProvider.future);
      final ticket = tickets.firstWhere(
        (t) => t['number'] == ticketNumber,
        orElse: () => <String, dynamic>{},
      );

      if (!mounted) return;
      if (ticket.isNotEmpty && ticket['questions'] is List) {
        final rawQuestions = ticket['questions'] as List;
        final ticketQuestions = _convertQuestionsToMap(rawQuestions);
        if (ticketQuestions.isNotEmpty) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TrainingScreen(
                questions: ticketQuestions,
                title: 'Билет $ticketNumber',
                startIndex: questionIndex.clamp(0, ticketQuestions.length - 1),
              ),
            ),
          );
          if (mounted && widget.isActive && _controller != null && _isInitialized) {
            _controller!.play();
            setState(() => _isPlaying = true);
          }
        }
      }
      return;
    }

    // 3. Если это тема
    if (widget.reel.targetType == 'topic' &&
        widget.reel.targetTopicId != null) {
      final topicId = widget.reel.targetTopicId!;
      final topics = await ref.read(topicsProvider.future);
      final topic = topics.firstWhere(
        (t) =>
            t['id']?.toString() == topicId ||
            t['name']?.toString().contains(topicId) == true,
        orElse: () => topics.isNotEmpty ? topics.first : <String, dynamic>{},
      );

      if (!mounted) return;
      if (topic.isNotEmpty && topic['questions'] is List) {
        final rawQuestions = topic['questions'] as List;
        final topicQuestions = _convertQuestionsToMap(rawQuestions);
        if (topicQuestions.isNotEmpty) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TrainingScreen(
                questions: topicQuestions,
                title: topic['name'] as String? ?? 'Тема $topicId',
              ),
            ),
          );
          if (mounted && widget.isActive && _controller != null && _isInitialized) {
            _controller!.play();
            setState(() => _isPlaying = true);
          }
        }
      }
    }
  }

  List<Map<String, dynamic>> _convertQuestionsToMap(List questions) {
    return questions.map((q) {
      if (q is Map<String, dynamic>) return q;
      return {
        'id': q.id,
        'question': q.question,
        'answers': q.answers
            .map(
              (a) => {
                'text': a.text,
                'correct': a.isCorrect,
              },
            )
            .toList(),
        'comment': q.comment ?? '',
        'pddPoints': q.pddPoints ?? [],
        'image': q.image,
        'topic': q.topic ?? [],
        'ticketNumber': q.ticketNumber,
      };
    }).toList();
  }

  String _formatCount(int count, String fallback) {
    if (count <= 0) return fallback;
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1).replaceAll('.0', '')} млн';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1).replaceAll('.0', '')} тыс.';
    }
    return count.toString();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _onScrubStart(double localDx, double width) {
    if (_controller == null || !_isInitialized) return;
    HapticFeedbackHelper.select();
    _wasPlayingBeforeScrub = _controller!.value.isPlaying;
    _controller?.pause();
    final progress = (localDx / width).clamp(0.0, 1.0);
    setState(() {
      _isScrubbing = true;
      _scrubProgress = progress;
    });
  }

  void _onScrubUpdate(double localDx, double width) {
    if (_controller == null || !_isInitialized) return;
    final progress = (localDx / width).clamp(0.0, 1.0);
    setState(() {
      _scrubProgress = progress;
    });

    // Плавный seek без фризов: троттлинг каждые 80мс
    final now = DateTime.now();
    if (now.difference(_lastSeekTime).inMilliseconds >= 80) {
      _lastSeekTime = now;
      final totalMs = _controller!.value.duration.inMilliseconds;
      _controller?.seekTo(Duration(milliseconds: (totalMs * progress).round()));
    }
  }

  void _onScrubEnd() async {
    if (_controller == null || !_isInitialized) return;
    HapticFeedbackHelper.select();
    final totalMs = _controller!.value.duration.inMilliseconds;
    await _controller?.seekTo(
      Duration(milliseconds: (totalMs * _scrubProgress).round()),
    );
    if (_wasPlayingBeforeScrub) {
      _controller?.play();
    }
    if (mounted) {
      setState(() {
        _isScrubbing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final totalLikes =
        widget.reel.likesCount + (widget.isLiked ? 1 : 0);
    final totalSaves =
        widget.reel.savesCount + (widget.isSaved ? 1 : 0);
    final totalShares = widget.sharesCount;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Видеоплеер
        GestureDetector(
          onTap: _togglePlayPause,
          onDoubleTap: _handleDoubleTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: Colors.black,
            child: _isInitialized && _controller != null
                ? Center(
                    child: SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _controller!.value.size.width > 0
                              ? _controller!.value.size.width
                              : size.width,
                          height: _controller!.value.size.height > 0
                              ? _controller!.value.size.height
                              : size.height,
                          child: VideoPlayer(_controller!),
                        ),
                      ),
                    ),
                  )
                : const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accent,
                      strokeWidth: 2.5,
                    ),
                  ),
          ),
        ),

        // 2. Градиентные тени для читаемости элементов
        IgnorePointer(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x55000000),
                  Colors.transparent,
                  Colors.transparent,
                  Color(0x88000000),
                ],
                stops: [0.0, 0.12, 0.65, 1.0],
              ),
            ),
          ),
        ),

        // 3. Анимация двойного тапа (всплывающее сердце)
        if (_showHeartBurst)
          Center(
            child: AnimatedBuilder(
              animation: _heartAnimController,
              builder: (context, child) {
                return Opacity(
                  opacity: _heartOpacityAnimation.value,
                  child: Transform.scale(
                    scale: _heartScaleAnimation.value,
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFFFE2C55),
                      size: 110,
                      shadows: [
                        BoxShadow(
                          color: Color(0x66FE2C55),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

        // 4. Индикатор паузы / старта по центру (чистая иконка, без фонового круга)
        if (_showPlayPauseIcon && !_isScrubbing)
          Center(
            child: Icon(
              _isPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: Colors.white.withValues(alpha: 0.85),
              size: 76,
              shadows: const [
                Shadow(
                  offset: Offset(0, 2),
                  blurRadius: 8,
                  color: Color(0x55000000),
                ),
              ],
            ),
          ),

        // 5. Всплывающий индикатор тайминга при перемотке
        if (_isScrubbing && _controller != null)
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _controller!,
            builder: (context, value, child) {
              final dur = value.duration;
              final scrubTime = Duration(
                milliseconds: (dur.inMilliseconds * _scrubProgress).round(),
              );
              return Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xCC000000),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatDuration(scrubTime),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Text(
                        ' / ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white54,
                        ),
                      ),
                      Text(
                        _formatDuration(dur),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

        // 6. Правая панель действий в стиле TikTok с мягкими тенями
        Positioned(
          right: 12,
          bottom: 28,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Кнопка Лайк (сплошное залитое сердце с мягкой тенью)
              _buildTikTokActionButton(
                iconWidget: Icon(
                  Icons.favorite_rounded,
                  color: widget.isLiked
                      ? const Color(0xFFFE2C55)
                      : Colors.white,
                  size: 34,
                  shadows: _subtleShadows,
                ),
                label: _formatCount(totalLikes, 'Нравится'),
                onTap: () {
                  HapticFeedbackHelper.tap();
                  widget.onToggleLike();
                },
              ),
              const SizedBox(height: 18),

              // Кнопка Сохранить (сплошная залитая закладка с мягкой тенью)
              _buildTikTokActionButton(
                iconWidget: Icon(
                  Icons.bookmark_rounded,
                  color: widget.isSaved
                      ? const Color(0xFFFACE15)
                      : Colors.white,
                  size: 34,
                  shadows: _subtleShadows,
                ),
                label: _formatCount(totalSaves, 'Сохранить'),
                onTap: () {
                  HapticFeedbackHelper.tap();
                  widget.onToggleSave();
                },
              ),
              const SizedBox(height: 18),

              // Кнопка Поделиться (изогнутая стрелка репоста с мягкой тенью)
              _buildTikTokActionButton(
                iconWidget: Transform.scale(
                  scaleX: -1,
                  child: const Icon(
                    Icons.reply_rounded,
                    color: Colors.white,
                    size: 36,
                    shadows: _subtleShadows,
                  ),
                ),
                label: _formatCount(totalShares, 'Поделиться'),
                onTap: () {
                  HapticFeedbackHelper.tap();
                  widget.onShare();
                },
              ),
              const SizedBox(height: 18),

              // Кнопка Звук (сплошной динамик с мягкой тенью)
              _buildTikTokActionButton(
                iconWidget: Icon(
                  widget.isMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 30,
                  shadows: _subtleShadows,
                ),
                label: widget.isMuted ? 'Выкл' : 'Вкл',
                onTap: () {
                  HapticFeedbackHelper.tap();
                  widget.onToggleMute();
                },
              ),
            ],
          ),
        ),

        // 7. Нижний блок — ТОЛЬКО интерактивная кнопка-ссылка (БЕЗ ВСЯКИХ ТЕНЕЙ, чисто синяя)
        Positioned(
          left: 16,
          right: 86,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.reel.targetType == 'signs' ||
                  widget.reel.targetSignCategory != null)
                _buildDeepLinkBadge(
                  icon: Icons.signpost_rounded,
                  text: widget.reel.targetSignCategory ?? 'Знаки',
                  onTap: _openDeepLink,
                )
              else if (widget.reel.targetType == 'ticket' &&
                  widget.reel.targetTicket != null)
                _buildDeepLinkBadge(
                  icon: Icons.quiz_rounded,
                  text:
                      'Билет ${widget.reel.targetTicket}${widget.reel.targetQuestion != null ? ', Вопрос ${widget.reel.targetQuestion}' : ''}',
                  onTap: _openDeepLink,
                )
              else if (widget.reel.targetType == 'topic' &&
                  widget.reel.targetTopicId != null)
                _buildDeepLinkBadge(
                  icon: Icons.menu_book_rounded,
                  text: 'Тема ${widget.reel.targetTopicId}',
                  onTap: _openDeepLink,
                ),
            ],
          ),
        ),

        // 8. Удобный и плавный прогресс-бар перемотки (автоматически плывет в реальном времени)
        if (_isInitialized && _controller != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _controller!,
              builder: (context, value, child) {
                final duration = value.duration;
                final position = value.position;
                final playbackProgress = duration.inMilliseconds > 0
                    ? (position.inMilliseconds / duration.inMilliseconds)
                        .clamp(0.0, 1.0)
                    : 0.0;
                final displayProgress =
                    _isScrubbing ? _scrubProgress : playbackProgress;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final barWidth = constraints.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) =>
                          _onScrubStart(details.localPosition.dx, barWidth),
                      onTapUp: (_) => _onScrubEnd(),
                      onHorizontalDragStart: (details) =>
                          _onScrubStart(details.localPosition.dx, barWidth),
                      onHorizontalDragUpdate: (details) =>
                          _onScrubUpdate(details.localPosition.dx, barWidth),
                      onHorizontalDragEnd: (_) => _onScrubEnd(),
                      onHorizontalDragCancel: _onScrubEnd,
                      child: Container(
                        height: 36, // Удобная широкая зона касания для пальца
                        alignment: Alignment.bottomLeft,
                        child: Stack(
                          alignment: Alignment.bottomLeft,
                          children: [
                            // Фоновая полоса трека (прижата к самому низу)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                height: _isScrubbing ? 4.5 : 2.5,
                                color: Colors.white24,
                              ),
                            ),
                            // Заполненная проигранная часть (прижата к самому низу)
                            Positioned(
                              left: 0,
                              bottom: 0,
                              width: (barWidth * displayProgress)
                                  .clamp(0.0, barWidth),
                              child: AnimatedContainer(
                                duration: _isScrubbing
                                    ? Duration.zero
                                    : const Duration(milliseconds: 100),
                                height: _isScrubbing ? 4.5 : 2.5,
                                color: Colors.white.withValues(
                                  alpha: _isScrubbing ? 1.0 : 0.85,
                                ),
                              ),
                            ),
                            // Точка-ползунок при активной перемотке (прижата к низу, растет вверх — без обрезки)
                            if (_isScrubbing)
                              Positioned(
                                left: (barWidth * displayProgress - 6).clamp(
                                  0.0,
                                  barWidth - 12,
                                ),
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x66000000),
                                        blurRadius: 4,
                                        offset: Offset(0, -1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  /// Кнопка действия в стиле TikTok (сплошная залитая иконка, мягкая естественная тень)
  Widget _buildTikTokActionButton({
    required Widget iconWidget,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.1,
              shadows: _subtleShadows,
            ),
          ),
        ],
      ),
    );
  }

  /// Интерактивный бейдж перехода к билету или знакам (чисто синий, БЕЗ ВСЯКИХ ТЕНЕЙ, без стрелки)
  Widget _buildDeepLinkBadge({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
