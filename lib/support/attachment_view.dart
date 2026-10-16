import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import '../core/api/api_client.dart';
import 'support_api.dart';
import 'support_models.dart';

final Map<String, Uint8List> _bytesCache = {};

Future<Uint8List> _load(SupportApi api, Attachment a) async => _bytesCache[a.id] ??= await api.download(a.id);

/// An attachment inside a conversation. Photos show a thumbnail and open full
/// screen. Videos and PDFs download and open in the phone's own viewer.
class AttachmentView extends StatelessWidget {
  const AttachmentView({super.key, required this.attachment});

  final Attachment attachment;

  Future<void> _open(BuildContext context) async {
    final api = context.read<SupportApi>();
    try {
      final bytes = await _load(api, attachment);
      if (!context.mounted) return;
      if (attachment.kind == AttachmentKind.image) {
        await showDialog<void>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: .92),
          builder: (_) => GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Center(child: InteractiveViewer(child: Image.memory(bytes))),
          ),
        );
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${attachment.id}_${attachment.name}');
      await file.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (context.mounted) showToast(context, e is ApiException ? e.message : 'Could not open the file.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (attachment.kind == AttachmentKind.image) {
      return GestureDetector(
        onTap: () => _open(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 150,
            height: 120,
            child: FutureBuilder<Uint8List>(
              future: _load(context.read<SupportApi>(), attachment),
              builder: (_, snap) {
                if (snap.hasData) return Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true);
                return Container(
                  color: AppColors.surfaceAlt,
                  child: Center(child: snap.hasError ? const Icon(Icons.broken_image_outlined, color: AppColors.textDim) : const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                );
              },
            ),
          ),
        ),
      );
    }
    final icon = attachment.kind == AttachmentKind.video ? Icons.play_circle_outline_rounded : Icons.picture_as_pdf_outlined;
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .25), borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(13, weight: FontWeight.w600)),
                  Text(formatBytes(attachment.size), style: AppText.body(11, color: AppColors.textDim)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
