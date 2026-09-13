import 'extracted_page_content.dart';

class OcrDocumentContext {
  final String id;
  final String title;
  final String text;
  final int pageCount;
  final List<ExtractedPageContent>? pages;
  final String actionType; // 'summarize', 'explain', 'quiz'
  final String? imagePath;
  final String? subjectId;
  final String? subjectName;
  final String? unitId;
  final String? unitName;

  const OcrDocumentContext({
    required this.id,
    required this.title,
    required this.text,
    this.pageCount = 1,
    this.pages,
    this.actionType = 'summarize',
    this.imagePath,
    this.subjectId,
    this.subjectName,
    this.unitId,
    this.unitName,
  });

  OcrDocumentContext copyWith({
    String? id,
    String? title,
    String? text,
    int? pageCount,
    List<ExtractedPageContent>? pages,
    String? actionType,
    String? imagePath,
    String? subjectId,
    String? subjectName,
    String? unitId,
    String? unitName,
  }) {
    return OcrDocumentContext(
      id: id ?? this.id,
      title: title ?? this.title,
      text: text ?? this.text,
      pageCount: pageCount ?? this.pageCount,
      pages: pages ?? this.pages,
      actionType: actionType ?? this.actionType,
      imagePath: imagePath ?? this.imagePath,
      subjectId: subjectId ?? this.subjectId,
      subjectName: subjectName ?? this.subjectName,
      unitId: unitId ?? this.unitId,
      unitName: unitName ?? this.unitName,
    );
  }
}
