import 'dart:developer';
import 'dart:io';
import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';
import 'package:video_trimmer/src/trim_viewer/trim_editor_painter.dart';
import 'package:video_trimmer/src/trimmer.dart';
import 'package:video_trimmer/src/utils/duration_style.dart';

import '../../utils/editor_drag_type.dart';
import '../trim_area_properties.dart';
import '../trim_editor_properties.dart';
import 'fixed_thumbnail_viewer.dart';

class FixedTrimViewer extends StatefulWidget {
  /// The Trimmer instance controlling the data.
  final Trimmer trimmer;

  /// For defining the total trimmer area width
  final double viewerWidth;

  /// For defining the total trimmer area height
  final double viewerHeight;

  /// For defining the maximum length of the output video.
  final Duration maxVideoLength;

  /// For defining the minimum length of the output video.
  final Duration minVideoLength;

  /// For showing the start and the end point of the
  /// video on top of the trimmer area.
  ///
  /// By default it is set to `true`.
  final bool showDuration;

  /// For providing a `TextStyle` to the
  /// duration text.
  ///
  /// By default it is set to `TextStyle(color: Colors.white)`
  final TextStyle durationTextStyle;

  /// For specifying a style of the duration
  ///
  /// By default it is set to `DurationStyle.FORMAT_HH_MM_SS`.
  final DurationStyle durationStyle;

  /// Callback to the video start position
  ///
  /// Returns the selected video start position in `milliseconds`.
  final Function(double startValue)? onChangeStart;

  /// Callback to the video end position.
  ///
  /// Returns the selected video end position in `milliseconds`.
  final Function(double endValue)? onChangeEnd;

  /// Callback to the video playback
  /// state to know whether it is currently playing or paused.
  ///
  /// Returns a `boolean` value. If `true`, video is currently
  /// playing, otherwise paused.
  final Function(bool isPlaying)? onChangePlaybackState;

  /// Properties for customizing the trim editor.
  final TrimEditorProperties editorProperties;

  /// Properties for customizing the fixed trim area.
  final FixedTrimAreaProperties areaProperties;

  final VoidCallback onThumbnailLoadingComplete;

  /// The initial trim start position. This can be used to set the
  /// initial start position of the trimmer area.
  ///
  /// See [initialEnd] for setting the initial end position.
  final Duration? initialStart;

  /// The initial trim end position. This can be used to set the
  /// initial end position of the trimmer area.
  ///
  /// See [initialStart] for setting the initial start position.
  final Duration? initialEnd;

  /// Widget for displaying the video trimmer.
  ///
  /// This has frame wise preview of the video with a
  /// slider for selecting the part of the video to be
  /// trimmed.
  ///
  /// The required parameters are [viewerWidth] & [viewerHeight]
  ///
  /// * [viewerWidth] to define the total trimmer area width.
  ///
  ///
  /// * [viewerHeight] to define the total trimmer area height.
  ///
  ///
  /// The optional parameters are:
  ///
  /// * [maxVideoLength] for specifying the maximum length of the
  /// output video.
  ///
  ///
  /// * [minVideoLength] for specifying the minimum length of the
  /// output video.
  ///
  ///
  /// * [showDuration] for showing the start and the end point of the
  /// video on top of the trimmer area. By default it is set to `true`.
  ///
  ///
  /// * [durationTextStyle] is for providing a `TextStyle` to the
  /// duration text. By default it is set to
  /// `TextStyle(color: Colors.white)`
  ///
  ///
  /// * [onChangeStart] is a callback to the video start position.
  ///
  ///
  /// * [onChangeEnd] is a callback to the video end position.
  ///
  ///
  /// * [onChangePlaybackState] is a callback to the video playback
  /// state to know whether it is currently playing or paused.
  ///
  ///
  /// * [editorProperties] defines properties for customizing the trim editor.
  ///
  ///
  /// * [areaProperties] defines properties for customizing the fixed trim area.
  ///
  const FixedTrimViewer({
    super.key,
    required this.trimmer,
    required this.onThumbnailLoadingComplete,
    this.viewerWidth = 50.0 * 8,
    this.viewerHeight = 50,
    this.maxVideoLength = const Duration(milliseconds: 0),
    this.minVideoLength = const Duration(milliseconds: 0),
    this.showDuration = true,
    this.durationTextStyle = const TextStyle(color: Colors.white),
    this.durationStyle = DurationStyle.FORMAT_HH_MM_SS,
    this.onChangeStart,
    this.onChangeEnd,
    this.onChangePlaybackState,
    this.editorProperties = const TrimEditorProperties(),
    this.areaProperties = const FixedTrimAreaProperties(),
    this.initialStart,
    this.initialEnd,
  });

  @override
  State<FixedTrimViewer> createState() => _FixedTrimViewerState();
}

class _FixedTrimViewerState extends State<FixedTrimViewer>
    with TickerProviderStateMixin {
  final _trimmerAreaKey = GlobalKey();

  File? get _videoFile => widget.trimmer.currentVideoFile;

  double _videoStartPos = 0.0;
  double _videoEndPos = 0.0;

  Offset _startPos = const Offset(0, 0);
  Offset _endPos = const Offset(0, 0);

  double _startFraction = 0.0;
  double _endFraction = 1.0;

  int _videoDuration = 0;
  int _currentPosition = 0;

  double _thumbnailViewerW = 0.0;
  double _thumbnailViewerH = 0.0;

  int _numberOfThumbnails = 0;

  late double _startCircleSize;
  late double _endCircleSize;
  late double _borderRadius;

  double? fraction;
  double? maxLengthPixels;
  double? minLengthPixels;

  FixedThumbnailViewer? thumbnailWidget;

  Animation<double>? _scrubberAnimation;
  AnimationController? _animationController;
  late Tween<double> _linearTween;

  /// Quick access to VideoPlayerController, only not null after [TrimmerEvent.initialized]
  /// has been emitted.
  VideoPlayerController get videoPlayerController =>
      widget.trimmer.videoPlayerController!;

  /// Keep track of the drag type, e.g. whether the user drags the left, center or
  /// right part of the frame. Set this in [_onDragStart] when the dragging starts.
  EditorDragType _dragType = EditorDragType.left;

  /// Whether the dragging is allowed. Dragging is ignore if the user's gesture is outside
  /// of the frame, to make the UI more realistic.
  bool _allowDrag = true;

  @override
  void initState() {
    super.initState();
    _startCircleSize = widget.editorProperties.circleSize;
    _endCircleSize = widget.editorProperties.circleSize;
    _borderRadius = widget.editorProperties.borderRadius;
    _thumbnailViewerH = widget.viewerHeight;
    log('thumbnailViewerW: $_thumbnailViewerW');
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final renderBox =
          _trimmerAreaKey.currentContext?.findRenderObject() as RenderBox?;
      final trimmerActualWidth = renderBox?.size.width;
      log('RENDER BOX: $trimmerActualWidth');
      if (trimmerActualWidth == null) return;
      _thumbnailViewerW = trimmerActualWidth;
      _initializeVideoController();
      videoPlayerController.seekTo(const Duration(milliseconds: 0));
      _numberOfThumbnails = (trimmerActualWidth / _thumbnailViewerH).round();
      log('numberOfThumbnails: $_numberOfThumbnails');
      log('thumbnailViewerW: $_thumbnailViewerW');
      setState(() {
        final FixedThumbnailViewer thumbnailWidget = FixedThumbnailViewer(
          videoFile: _videoFile!,
          videoDuration: _videoDuration,
          fit: widget.areaProperties.thumbnailFit,
          thumbnailHeight: _thumbnailViewerH,
          thumbnailWidth: _thumbnailViewerW / _numberOfThumbnails,
          numberOfThumbnails: _numberOfThumbnails,
          quality: widget.areaProperties.thumbnailQuality,
          onThumbnailLoadingComplete: widget.onThumbnailLoadingComplete,
        );
        this.thumbnailWidget = thumbnailWidget;
        Duration totalDuration = videoPlayerController.value.duration;

        Duration? initialEnd = widget.initialEnd;

        if (initialEnd != null) {
          assert(initialEnd <= totalDuration,
              "initialEnd must be less than or equal to the total duration of the video");
          if (initialEnd > totalDuration) {
            initialEnd = null;
          }
        }

        if (initialEnd != null &&
            initialEnd > const Duration(milliseconds: 0) &&
            initialEnd < totalDuration) {
          fraction = initialEnd.inMilliseconds / totalDuration.inMilliseconds;
        }

        if (widget.maxVideoLength > const Duration(milliseconds: 0) &&
            widget.maxVideoLength < totalDuration) {
          final maxLengthFraction = widget.maxVideoLength.inMilliseconds /
              totalDuration.inMilliseconds;
          fraction ??= maxLengthFraction;
          maxLengthPixels = _thumbnailViewerW * maxLengthFraction;
        } else {
          maxLengthPixels = _thumbnailViewerW;
        }

        if (widget.minVideoLength > const Duration(milliseconds: 0) &&
            widget.minVideoLength < totalDuration) {
          final minLengthFraction = widget.minVideoLength.inMilliseconds /
              totalDuration.inMilliseconds;
          minLengthPixels = _thumbnailViewerW * minLengthFraction;
        } else {
          minLengthPixels = 0;
        }

        _videoEndPos = fraction != null
            ? _videoDuration.toDouble() * fraction!
            : _videoDuration.toDouble();

        widget.onChangeEnd!(_videoEndPos);

        _endPos = Offset(
          _thumbnailViewerW * (fraction ?? 1),
          _thumbnailViewerH,
        );

        final initialStart = widget.initialStart;

        if (initialStart != null &&
            initialStart > const Duration(milliseconds: 0) &&
            initialStart < totalDuration) {
          final videoStartFraction =
              initialStart.inMilliseconds / _videoDuration;

          _videoStartPos = _videoDuration.toDouble() * videoStartFraction;

          widget.onChangeStart!(_videoStartPos);

          _startPos = Offset(
            _thumbnailViewerW * videoStartFraction,
            0,
          );
        }

        // Defining the tween points
        _linearTween = Tween(begin: _startPos.dx, end: _endPos.dx);
        _animationController = AnimationController(
          vsync: this,
          duration:
              Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt()),
        );

        _scrubberAnimation = _linearTween.animate(_animationController!)
          ..addListener(() {
            setState(() {});
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _animationController!.stop();
            }
          });
      });
    });
  }

  Future<void> _initializeVideoController() async {
    if (_videoFile != null) {
      videoPlayerController.addListener(() {
        final bool isPlaying = videoPlayerController.value.isPlaying;

        if (isPlaying) {
          widget.onChangePlaybackState!(true);
          setState(() {
            _currentPosition =
                videoPlayerController.value.position.inMilliseconds;

            if (_currentPosition > _videoEndPos.toInt()) {
              videoPlayerController.pause();
              widget.onChangePlaybackState!(false);
              _animationController!.stop();
            } else {
              if (!_animationController!.isAnimating) {
                widget.onChangePlaybackState!(true);
                _animationController!.forward();
              }
            }
          });
        } else {
          if (videoPlayerController.value.isInitialized) {
            if (_animationController != null) {
              if ((_scrubberAnimation?.value ?? 0).toInt() ==
                  (_endPos.dx).toInt()) {
                _animationController!.reset();
              }
              _animationController!.stop();
              widget.onChangePlaybackState!(false);
            }
          }
        }
      });

      videoPlayerController.setVolume(1.0);
      _videoDuration = videoPlayerController.value.duration.inMilliseconds;
    }
  }

  /// Called when the user starts dragging the frame, on either side on the whole frame.
  /// Determine which [EditorDragType] is used.
  void _onDragStart(DragStartDetails details) {
    debugPrint("_onDragStart");
    debugPrint(details.localPosition.toString());
    debugPrint((_startPos.dx - details.localPosition.dx).abs().toString());
    debugPrint((_endPos.dx - details.localPosition.dx).abs().toString());

    final startDifference = _startPos.dx - details.localPosition.dx;
    final endDifference = _endPos.dx - details.localPosition.dx;

    // First we determine whether the dragging motion should be allowed. The allowed
    // zone is widget.sideTapSize (left) + frame (center) + widget.sideTapSize (right)
    if (startDifference <= widget.editorProperties.sideTapSize &&
        endDifference >= -widget.editorProperties.sideTapSize) {
      _allowDrag = true;
    } else {
      debugPrint("Dragging is outside of frame, ignoring gesture...");
      _allowDrag = false;
      return;
    }

    // Now we determine which part is dragged
    if (startDifference == endDifference) {
      // If the drag is the same distance from the `_startPos.dx` and
      // `_endPos.dx`, we can assume that the points are the same.
      // A positive value means the drag is to the left, a negative value
      // means the drag is to the right.
      if (startDifference > 0) {
        _dragType = EditorDragType.left;
      } else {
        _dragType = EditorDragType.right;
      }
    } else {
      if (normalizedLocalPos.dx <=
          _startPos.dx + widget.editorProperties.sideTapSize) {
        // If the drag is closer to the `_endPos.dx` than the `_startPos.dx`,
        // we drag the right side instead.
        if (startDifference.abs() > endDifference.abs()) {
          _dragType = EditorDragType.right;
        } else {
          _dragType = EditorDragType.left;
        }
      } else if (normalizedLocalPos.dx <=
          _endPos.dx - widget.editorProperties.sideTapSize) {
        _dragType = EditorDragType.center;
      } else {
        _dragType = EditorDragType.right;
      }
    }
    _seekVideoBasedOnDragType();
  }

  /// Called during dragging, only executed if [_allowDrag] was set to true in
  /// [_onDragStart].
  /// Makes sure the limits are respected.
  void _onDragUpdate(DragUpdateDetails details) {
    if (!_allowDrag) return;

    final dragDeltaDx = details.delta.dx;
    final dragLocalPosDx = details.localPosition.dx;

    if (_dragType == EditorDragType.left) {
      _startCircleSize = widget.editorProperties.circleSizeOnDrag;

      final double leftLimit = max(0.0, _endPos.dx - maxLengthPixels!);
      final double rightLimit = _endPos.dx - minLengthPixels!;

      final ignoreUpdate = (dragLocalPosDx < leftLimit && dragDeltaDx > 0) ||
          (dragLocalPosDx > rightLimit && dragDeltaDx < 0);

      if (!ignoreUpdate) {
        final newStartPos =
            (_startPos.dx + dragDeltaDx).clamp(leftLimit, rightLimit);

        _startPos = Offset(newStartPos, _startPos.dy + details.delta.dy);
        _onStartDragged();
      }
    } else if (_dragType == EditorDragType.center) {
      _startCircleSize = widget.editorProperties.circleSizeOnDrag;
      _endCircleSize = widget.editorProperties.circleSizeOnDrag;

      final currentLength = _endPos.dx - _startPos.dx;
      final newStartPos = (_startPos.dx + dragDeltaDx)
          .clamp(0.0, _thumbnailViewerW - currentLength);
      final newEndPos =
          (_endPos.dx + dragDeltaDx).clamp(currentLength, _thumbnailViewerW);

      final ignoreUpdate =
          newStartPos == _startPos.dx && newEndPos == _endPos.dx;

      if (!ignoreUpdate) {
        _startPos = Offset(newStartPos, _startPos.dy + details.delta.dy);
        _endPos = Offset(newEndPos, _endPos.dy + details.delta.dy);
        _onStartDragged();
        _onEndDragged();
      }
    } else {
      _endCircleSize = widget.editorProperties.circleSizeOnDrag;

      final double leftLimit = _startPos.dx + minLengthPixels!;
      final double rightLimit =
          min(_thumbnailViewerW, _startPos.dx + maxLengthPixels!);

      final ignoreUpdate = (dragLocalPosDx < leftLimit && dragDeltaDx > 0) ||
          (dragLocalPosDx > rightLimit && dragDeltaDx < 0);

      if (!ignoreUpdate) {
        final newEndPosition =
            (_endPos.dx + dragDeltaDx).clamp(leftLimit, rightLimit);

        _endPos = Offset(newEndPosition, _endPos.dy + details.delta.dy);
        _onEndDragged();
      }
    }
    setState(() {});
    _seekVideoBasedOnDragType();
  }

  void _onStartDragged() {
    _startFraction = (_startPos.dx / _thumbnailViewerW);
    _videoStartPos = _videoDuration * _startFraction;
    widget.onChangeStart!(_videoStartPos);
    _linearTween.begin = _startPos.dx;
    _animationController!.duration =
        Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
    _animationController!.reset();
  }

  void _onEndDragged() {
    _endFraction = _endPos.dx / _thumbnailViewerW;
    _videoEndPos = _videoDuration * _endFraction;
    widget.onChangeEnd!(_videoEndPos);
    _linearTween.end = _endPos.dx;
    _animationController!.duration =
        Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
    _animationController!.reset();
  }

  /// Drag gesture ended, update UI accordingly.
  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _startCircleSize = widget.editorProperties.circleSize;
      _endCircleSize = widget.editorProperties.circleSize;
    });

    _seekVideoBasedOnDragType();
  }

  void _seekVideoBasedOnDragType() {
    setState(() {
      if (_dragType == EditorDragType.right) {
        videoPlayerController.pause();
        videoPlayerController
            .seekTo(Duration(milliseconds: _videoEndPos.toInt()));
      } else {
        videoPlayerController.pause();
        videoPlayerController
            .seekTo(Duration(milliseconds: _videoStartPos.toInt()));
      }
    });
  }

  @override
  void dispose() {
    videoPlayerController.pause();
    widget.onChangePlaybackState!(false);
    if (_videoFile != null) {
      videoPlayerController.setVolume(0.0);
      widget.onChangePlaybackState!(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          widget.showDuration
              ? SizedBox(
                  width: _thumbnailViewerW,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.max,
                      children: <Widget>[
                        Text(
                          Duration(milliseconds: _videoStartPos.toInt())
                              .format(widget.durationStyle),
                          style: widget.durationTextStyle,
                        ),
                        videoPlayerController.value.isPlaying
                            ? Text(
                                Duration(milliseconds: _currentPosition.toInt())
                                    .format(widget.durationStyle),
                                style: widget.durationTextStyle,
                              )
                            : Container(),
                        Text(
                          Duration(milliseconds: _videoEndPos.toInt())
                              .format(widget.durationStyle),
                          style: widget.durationTextStyle,
                        ),
                      ],
                    ),
                  ),
                )
              : Container(),
          CustomPaint(
            foregroundPainter: TrimEditorPainter(
              startPos: _startPos,
              endPos: _endPos,
              scrubberAnimationDx: _scrubberAnimation?.value ?? 0,
              startCircleSize: _startCircleSize,
              endCircleSize: _endCircleSize,
              borderRadius: _borderRadius,
              borderWidth: widget.editorProperties.borderWidth,
              scrubberWidth: widget.editorProperties.scrubberWidth,
              circlePaintColor: widget.editorProperties.circlePaintColor,
              borderPaintColor: widget.editorProperties.borderPaintColor,
              scrubberPaintColor: widget.editorProperties.scrubberPaintColor,
            ),
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(widget.areaProperties.borderRadius),
              child: Container(
                key: _trimmerAreaKey,
                color: Colors.grey[900],
                height: _thumbnailViewerH,
                width: _thumbnailViewerW == 0.0
                    ? widget.viewerWidth
                    : _thumbnailViewerW,
                child: thumbnailWidget ?? Container(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
