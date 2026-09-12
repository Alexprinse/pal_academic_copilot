import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ocr_service.dart';
import '../theme/app_theme.dart';

class OcrScannerScreen extends StatefulWidget {
  final Function(int, {String? initialQuery}) onNavigateToBrain;

  const OcrScannerScreen({super.key, required this.onNavigateToBrain});

  @override
  State<OcrScannerScreen> createState() => _OcrScannerScreenState();
}

class _OcrScannerScreenState extends State<OcrScannerScreen> {
  final OcrService _ocrService = OcrService.instance;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ocrService.addListener(_onOcrUpdate);
    if (_ocrService.lastResult != null) {
      _textController.text = _ocrService.lastResult!.text;
    }
  }

  @override
  void dispose() {
    _ocrService.removeListener(_onOcrUpdate);
    _textController.dispose();
    super.dispose();
  }

  void _onOcrUpdate() {
    if (mounted) {
      if (_ocrService.lastResult != null) {
        _textController.text = _ocrService.lastResult!.text;
      }
      setState(() {});
    }
  }

  Future<void> _capture(ImageSource source) async {
    try {
      final res = await _ocrService.scanImage(source);
      if (res != null && mounted) {
        _textController.text = res.text;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.cardDark,
          content: Text('OCR Error: $e',
              style: const TextStyle(color: AppTheme.redAccent)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastResult = _ocrService.lastResult;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Textbook & Notes OCR'),
            Text(
              'Google ML Kit On-Device Vision',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear, color: AppTheme.textMuted),
            tooltip: 'Clear',
            onPressed: () {
              _ocrService.clear();
              _textController.clear();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Latency & Hardware telemetry pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.speed,
                      color: AppTheme.greenAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      lastResult != null
                          ? 'OCR Latency: ${lastResult.processingTimeMs} ms • ${lastResult.blockCount} Text Blocks Recognized'
                          : 'On-Device Latin Recognition (< 200ms latency, zero cloud)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Image Preview (if present)
            if (lastResult?.imagePath != null &&
                File(lastResult!.imagePath!).existsSync())
              Container(
                height: 140,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    File(lastResult.imagePath!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            // Extracted Text Box
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recognized Equations & Text',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (_ocrService.isProcessing)
                          const Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.cyanAccent,
                                ),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Scanning...',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.cyanAccent,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const Divider(color: AppTheme.cardBorder, height: 20),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        maxLines: null,
                        expands: true,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText:
                              'Scan textbook pages, homework questions, or handwritten notes using the Camera or Gallery buttons below...',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Action Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.calculate_outlined,
                      size: 16, color: AppTheme.cyanAccent),
                  label: const Text('Explain & Solve Step-by-Step'),
                  onPressed: _textController.text.trim().isNotEmpty
                      ? () {
                          widget.onNavigateToBrain(
                            4,
                            initialQuery:
                                'Solve and explain the following question step-by-step with proofs:\n\n${_textController.text.trim()}',
                          );
                        }
                      : null,
                ),
                ActionChip(
                  avatar: const Icon(Icons.summarize_outlined,
                      size: 16, color: AppTheme.amberAccent),
                  label: const Text('Summarize Notes'),
                  onPressed: _textController.text.trim().isNotEmpty
                      ? () {
                          widget.onNavigateToBrain(
                            4,
                            initialQuery:
                                'Summarize these textbook notes into bullet points and key formulas:\n\n${_textController.text.trim()}',
                          );
                        }
                      : null,
                ),
                ActionChip(
                  avatar: const Icon(Icons.quiz_outlined,
                      size: 16, color: AppTheme.purpleAccent),
                  label: const Text('Create 3 Quiz Qs'),
                  onPressed: _textController.text.trim().isNotEmpty
                      ? () {
                          widget.onNavigateToBrain(
                            4,
                            initialQuery:
                                'Generate 3 conceptual exam questions based on this scanned excerpt:\n\n${_textController.text.trim()}',
                          );
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Capture Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cyanAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera Scan',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _capture(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      side: const BorderSide(color: AppTheme.cardBorder),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Choose Photo'),
                    onPressed: () => _capture(ImageSource.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
