import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import 'support_api.dart';
import 'support_models.dart';

/// A file the player picked. It uploads as soon as it is picked.
class PendingFile {
  PendingFile({required this.name, required this.path, required this.kind, required this.size});

  final String name;
  final String path;
  final AttachmentKind kind;
  final int size;
  Attachment? uploaded;
  bool uploading = true;
  String? error;
}

/// Holds the files for one appeal or message: picks, uploads, retries, removes.
///
/// ```dart
/// final files = AttachmentsController(context.read<SupportApi>());
/// AttachmentStrip(controller: files)        // thumbnails + add button
/// await api.reply(id, text, files.ids)      // only uploaded files
/// ```
class AttachmentsController extends ChangeNotifier {
  AttachmentsController(this._api);

  final SupportApi _api;
  final List<PendingFile> files = [];

  /// Set to show a message (too big, too many...). The widget turns it into a toast.
  String? notice;

  bool get busy => files.any((f) => f.uploading);
  bool get hasFailed => files.any((f) => f.error != null);
  List<String> get ids => [for (final f in files) if (f.uploaded != null) f.uploaded!.id];
  int get slotsLeft => SupportApi.maxFiles - files.length;
  bool get isEmpty => files.isEmpty;

  Future<void> add(Iterable<({String path, String name})> picked) async {
    for (final p in picked) {
      if (slotsLeft <= 0) {
        _say('You can attach up to ${SupportApi.maxFiles} files.');
        break;
      }
      final size = await File(p.path).length();
      if (size > SupportApi.maxMb * 1024 * 1024) {
        _say('${p.name} is over ${SupportApi.maxMb} MB.');
        continue;
      }
      if (size == 0) continue;
      final f = PendingFile(name: p.name, path: p.path, kind: kindFromName(p.name), size: size);
      files.add(f);
      notifyListeners();
      unawaited(_upload(f));
    }
  }

  Future<void> _upload(PendingFile f) async {
    f
      ..uploading = true
      ..error = null;
    notifyListeners();
    try {
      f.uploaded = await _api.upload(f.path, f.name);
    } catch (e) {
      f.error = e is ApiException ? e.message : 'Upload failed.';
    }
    f.uploading = false;
    notifyListeners();
  }

  void retry(PendingFile f) => unawaited(_upload(f));

  void remove(PendingFile f) {
    files.remove(f);
    notifyListeners();
  }

  void clear() {
    files.clear();
    notifyListeners();
  }

  void _say(String m) {
    notice = m;
    notifyListeners();
  }

  // ---- pickers ----------------------------------------------------------------

  final ImagePicker _picker = ImagePicker();

  Future<void> pickPhotos() async {
    final xs = await _picker.pickMultiImage(imageQuality: 88, maxWidth: 2400);
    await add([for (final x in xs.take(slotsLeft < 0 ? 0 : slotsLeft)) (path: x.path, name: x.name)]);
  }

  Future<void> takePhoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 88, maxWidth: 2400);
    if (x != null) await add([(path: x.path, name: x.name)]);
  }

  Future<void> pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 3));
    if (x != null) await add([(path: x.path, name: x.name)]);
  }

  Future<void> recordVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 2));
    if (x != null) await add([(path: x.path, name: x.name)]);
  }

  Future<void> pickPdf() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf'], allowMultiple: true);
    if (r == null) return;
    await add([for (final f in r.files) if (f.path != null) (path: f.path!, name: f.name)]);
  }
}

/// The "add a file" sheet. Each row opens the system picker.
Future<void> showAttachSheet(BuildContext context, AttachmentsController c) {
  Widget row(IconData icon, String title, String sub, Future<void> Function() run) {
    return ListRowTile(
      icon: icon,
      title: title,
      subtitle: sub,
      onTap: () async {
        Navigator.of(context).pop();
        try {
          await run();
        } catch (_) {
          c._say('Could not open that. Check the app has permission in Settings.');
        }
      },
    );
  }

  return showAppBottomSheet<void>(
    context,
    title: 'Add a file',
    child: Column(
      children: [
        ListGroup(
          children: [
            row(Icons.photo_library_outlined, 'Photos', 'Screenshots or pictures', c.pickPhotos),
            row(Icons.photo_camera_outlined, 'Take a photo', 'Use the camera', c.takePhoto),
            row(Icons.video_library_outlined, 'Video', 'From your library', c.pickVideo),
            row(Icons.videocam_outlined, 'Record a video', 'Show us what happened', c.recordVideo),
            row(Icons.picture_as_pdf_outlined, 'PDF document', 'Receipts, statements', c.pickPdf),
          ],
        ),
        const SizedBox(height: 10),
        Text('Up to ${SupportApi.maxFiles} files, ${SupportApi.maxMb} MB each. Photos, videos and PDFs only.', style: AppText.body(12, color: AppColors.textDim)),
      ],
    ),
  );
}

/// Thumbnails of the picked files, with progress, retry and remove, plus the
/// "Add files" button. Shows the controller's notices as toasts.
class AttachmentStrip extends StatefulWidget {
  const AttachmentStrip({super.key, required this.controller, this.label = 'Add photos, video or PDF', this.showAdd = true});

  final AttachmentsController controller;
  final String label;

  /// `false` when the screen has its own attach button (the chat composer).
  final bool showAdd;

  @override
  State<AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends State<AttachmentStrip> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final n = widget.controller.notice;
    if (n != null) {
      widget.controller.notice = null;
      showSnack(n);
    }
    setState(() {});
  }

  void showSnack(String m) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceRaised,
      content: Text(m, style: AppText.body(14, color: AppColors.loss)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.files.isNotEmpty)
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: c.files.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _Thumb(file: c.files[i], onRemove: () => c.remove(c.files[i]), onRetry: () => c.retry(c.files[i])),
            ),
          ),
        if (c.files.isNotEmpty && widget.showAdd) const SizedBox(height: 10),
        if (widget.showAdd && c.slotsLeft > 0)
          PillButton(label: widget.label, icon: Icons.attach_file_rounded, onPressed: () => showAttachSheet(context, c)),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.file, required this.onRemove, required this.onRetry});

  final PendingFile file;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = file.error != null;
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(color: AppColors.surfaceAlt, border: Border.all(color: failed ? AppColors.loss : AppColors.line), borderRadius: BorderRadius.circular(14)),
                child: file.kind == AttachmentKind.image
                    ? Image.file(File(file.path), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.image_outlined, color: AppColors.textDim))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(file.kind == AttachmentKind.video ? Icons.movie_outlined : Icons.picture_as_pdf_outlined, color: AppColors.textMuted, size: 28),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(10, color: AppColors.textDim)),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          if (file.uploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(14)),
                child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))),
              ),
            ),
          if (failed)
            Positioned.fill(
              child: GestureDetector(
                onTap: onRetry,
                child: Container(
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded, color: AppColors.loss),
                      Text('Retry', style: AppText.body(11, color: AppColors.loss, weight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            right: -6,
            top: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle, border: Border.all(color: AppColors.lineStrong)),
                child: Icon(Icons.close_rounded, size: 14, color: AppColors.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
