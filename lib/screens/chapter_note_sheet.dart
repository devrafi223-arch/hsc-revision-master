import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../services/notes_repository.dart';

/// Per-chapter special note: text OR photo OR both. Opens as a
/// Material modal bottom sheet; loads any existing note for the chapter.
class ChapterNoteSheet {
  static Future<void> show(
    BuildContext context, {
    required String chapterId,
    required String chapterTitle,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ChapterNoteSheetBody(
        chapterId: chapterId,
        chapterTitle: chapterTitle,
      ),
    );
  }
}

class _ChapterNoteSheetBody extends StatefulWidget {
  const _ChapterNoteSheetBody({
    required this.chapterId,
    required this.chapterTitle,
  });

  final String chapterId;
  final String chapterTitle;

  @override
  State<_ChapterNoteSheetBody> createState() => _ChapterNoteSheetBodyState();
}

class _ChapterNoteSheetBodyState extends State<_ChapterNoteSheetBody> {
  final TextEditingController _textController = TextEditingController();
  String? _localPhotoPath;
  String? _savedPhotoUrl;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final note = await NotesRepository.instance.getNote(widget.chapterId);
      if (!mounted) return;
      setState(() {
        _textController.text = (note?['text'] as String?) ?? '';
        _savedPhotoUrl = note?['photoUrl'] as String?;
        _localPhotoPath = note?['localPhotoPath'] as String?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (picked == null) return;
    setState(() {
      _localPhotoPath = picked.path;
      _savedPhotoUrl = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await NotesRepository.instance.saveNote(
        chapterId: widget.chapterId,
        text: _textController.text.trim(),
        localPhotoPath: _localPhotoPath,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the note. ${e.toString()}';
      });
    }
  }

  Widget _photoPreview() {
    if (_localPhotoPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          File(_localPhotoPath!),
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }
    if (_savedPhotoUrl != null && _savedPhotoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          _savedPhotoUrl!,
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: isDark ? JimColors.darkSurface : JimColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? JimColors.darkLine : JimColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Note — ${widget.chapterTitle}',
            style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Text or photo, or both — for your next revision.',
            style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            Expanded(
              child: ListView(
                children: [
                  SizedBox(
                    height: 160,
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: jimFieldDecoration(
                        dark: isDark,
                        hint: 'Write the chapter in your own words…',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _photoPreview(),
                  if (_localPhotoPath != null || _savedPhotoUrl != null)
                    const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.photo, size: 18),
                    label: const Text('Add a photo'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: base.copyWith(
                        fontSize: 14,
                        color: Colors.red,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving || _loading ? null : _save,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(_saving ? 'Saving…' : 'Save note'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small rose "Note" chip shown on a chapter card when a note exists
/// for that chapter. Shows nothing (zero size) when there is no note.
class ChapterNoteBadge extends StatelessWidget {
  const ChapterNoteBadge({required this.chapterId, super.key});

  final String chapterId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: NotesRepository.instance.getNote(chapterId),
      builder: (context, snapshot) {
        final note = snapshot.data;
        final hasNote = note != null &&
            (((note['text'] as String?) ?? '').trim().isNotEmpty ||
                (note['photoUrl'] as String?)?.isNotEmpty == true ||
                (note['localPhotoPath'] as String?)?.isNotEmpty == true);
        if (!hasNote) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: JimColors.rose,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'Note',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}
