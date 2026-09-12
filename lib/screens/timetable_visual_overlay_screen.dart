import 'dart:io';
import 'package:flutter/material.dart';
import '../models/parsed_timetable_entry.dart';
import '../models/timetable_ocr_item.dart';
import '../theme/app_theme.dart';

class TimetableVisualOverlayScreen extends StatefulWidget {
  final String imagePath;
  final List<TimetableOcrItem> dayHeaders;
  final List<TimetableOcrItem> timeHeaders;
  final List<ParsedTimetableEntry> entries;
  final List<Rect> cellRects;

  const TimetableVisualOverlayScreen({
    super.key,
    required this.imagePath,
    required this.dayHeaders,
    required this.timeHeaders,
    required this.entries,
    required this.cellRects,
  });

  @override
  State<TimetableVisualOverlayScreen> createState() =>
      _TimetableVisualOverlayScreenState();
}

class _TimetableVisualOverlayScreenState
    extends State<TimetableVisualOverlayScreen> {
  bool _showOverlays = true;
  Size? _imageNaturalSize;

  @override
  void initState() {
    super.initState();
    _loadImageNaturalSize();
  }

  void _loadImageNaturalSize() {
    final image = Image.file(File(widget.imagePath));
    image.image
        .resolve(const ImageConfiguration())
        .addListener(ImageStreamListener((info, _) {
      if (mounted) {
        setState(() {
          _imageNaturalSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Spatial Detection Overlay',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              'Pinch to zoom · Verified on-device',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showOverlays ? Icons.layers : Icons.layers_clear,
              color: _showOverlays ? AppTheme.primaryAccent : Colors.white60,
            ),
            tooltip:
                _showOverlays ? 'Hide Bounding Boxes' : 'Show Bounding Boxes',
            onPressed: () => setState(() => _showOverlays = !_showOverlays),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Legend bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF1E1E1E),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildLegendItem(const Color(0xFF2196F3),
                      'Days (${widget.dayHeaders.length})'),
                  _buildLegendItem(const Color(0xFFFF9800),
                      'Times (${widget.timeHeaders.length})'),
                  _buildLegendItem(const Color(0xFF4CAF50),
                      'Classes (${widget.entries.length})'),
                ],
              ),
            ),
            // Interactive image area
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: _imageNaturalSize == null
                      ? const CircularProgressIndicator(
                          color: AppTheme.primaryAccent)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final natural = _imageNaturalSize!;
                            // Calculate display rect of image keeping aspect ratio
                            final fitWidth = constraints.maxWidth;
                            final fitHeight = constraints.maxHeight;

                            final scaleX = fitWidth / natural.width;
                            final scaleY = fitHeight / natural.height;
                            final scale = scaleX < scaleY ? scaleX : scaleY;

                            final displayWidth = natural.width * scale;
                            final displayHeight = natural.height * scale;

                            return SizedBox(
                              width: displayWidth,
                              height: displayHeight,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    File(widget.imagePath),
                                    fit: BoxFit.contain,
                                  ),
                                  if (_showOverlays)
                                    CustomPaint(
                                      painter: _OverlayPainter(
                                        naturalSize: natural,
                                        displaySize:
                                            Size(displayWidth, displayHeight),
                                        dayHeaders: widget.dayHeaders,
                                        timeHeaders: widget.timeHeaders,
                                        entries: widget.entries,
                                        cellRects: widget.cellRects,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
              fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final Size naturalSize;
  final Size displaySize;
  final List<TimetableOcrItem> dayHeaders;
  final List<TimetableOcrItem> timeHeaders;
  final List<ParsedTimetableEntry> entries;
  final List<Rect> cellRects;

  _OverlayPainter({
    required this.naturalSize,
    required this.displaySize,
    required this.dayHeaders,
    required this.timeHeaders,
    required this.entries,
    required this.cellRects,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = displaySize.width / naturalSize.width;
    final scaleY = displaySize.height / naturalSize.height;

    Rect scaleRect(Rect r) {
      return Rect.fromLTRB(
        r.left * scaleX,
        r.top * scaleY,
        r.right * scaleX,
        r.bottom * scaleY,
      );
    }

    // 1. Draw Day Headers (Blue)
    final dayPaint = Paint()
      ..color = const Color(0xFF2196F3).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final dayBorder = Paint()
      ..color = const Color(0xFF2196F3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final item in dayHeaders) {
      final r = scaleRect(item.boundingBox);
      canvas.drawRect(r, dayPaint);
      canvas.drawRect(r, dayBorder);
    }

    // 2. Draw Time Headers (Amber)
    final timePaint = Paint()
      ..color = const Color(0xFFFF9800).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final timeBorder = Paint()
      ..color = const Color(0xFFFF9800)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final item in timeHeaders) {
      final r = scaleRect(item.boundingBox);
      canvas.drawRect(r, timePaint);
      canvas.drawRect(r, timeBorder);
    }

    // 3. Draw Class Cells (Green)
    final classPaint = Paint()
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final classBorder = Paint()
      ..color = const Color(0xFF4CAF50)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final entry in entries) {
      if (entry.sourceBoundingBox != null) {
        final r = scaleRect(entry.sourceBoundingBox!);
        canvas.drawRect(r, classPaint);
        canvas.drawRect(r, classBorder);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => true;
}
