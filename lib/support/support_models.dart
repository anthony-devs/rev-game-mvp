import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../model/model_json.dart';

/// Photo, video or PDF. Matches what the server accepts.
enum AttachmentKind { image, video, pdf }

AttachmentKind kindFromName(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return AttachmentKind.pdf;
  if (n.endsWith('.mp4') || n.endsWith('.mov') || n.endsWith('.m4v')) return AttachmentKind.video;
  return AttachmentKind.image;
}

/// A file already stored on the server (it has an id).
class Attachment extends Equatable {
  const Attachment({required this.id, required this.name, required this.kind, required this.size, this.mime = ''});

  final String id;
  final String name;
  final AttachmentKind kind;
  final int size;
  final String mime;

  factory Attachment.fromJson(Json j) => Attachment(
        id: parseString(j['id']) ?? '',
        name: parseString(j['name']) ?? 'file',
        kind: enumByName(AttachmentKind.values, j['kind'], AttachmentKind.image),
        size: parseInt(j['size']),
        mime: parseString(j['mime']) ?? '',
      );

  @override
  List<Object?> get props => [id];
}

String formatBytes(int n) => n >= 1048576 ? '${(n / 1048576).toStringAsFixed(1)} MB' : '${(n / 1024).clamp(1, 1e9).round()} KB';

enum TicketStatus { open, pending, solved, closed }

extension TicketStatusX on TicketStatus {
  String get label {
    switch (this) {
      case TicketStatus.open:
        return 'Open';
      case TicketStatus.pending:
        return 'Reply received';
      case TicketStatus.solved:
        return 'Solved';
      case TicketStatus.closed:
        return 'Closed';
    }
  }
}

/// What a ticket is about. `id` is what the server stores.
enum TicketCategory { account, credits, gameplay, fairness, restriction, technical, other }

extension TicketCategoryX on TicketCategory {
  String get label {
    switch (this) {
      case TicketCategory.account:
        return 'Account & sign-in';
      case TicketCategory.credits:
        return 'Credits & balance';
      case TicketCategory.gameplay:
        return 'A game or round';
      case TicketCategory.fairness:
        return 'Fairness & results';
      case TicketCategory.restriction:
        return 'Ban or restriction';
      case TicketCategory.technical:
        return 'Bug or problem';
      case TicketCategory.other:
        return 'Something else';
    }
  }

  IconData get icon {
    switch (this) {
      case TicketCategory.account:
        return Icons.person_outline_rounded;
      case TicketCategory.credits:
        return Icons.toll_rounded;
      case TicketCategory.gameplay:
        return Icons.casino_outlined;
      case TicketCategory.fairness:
        return Icons.verified_user_outlined;
      case TicketCategory.restriction:
        return Icons.block_rounded;
      case TicketCategory.technical:
        return Icons.bug_report_outlined;
      case TicketCategory.other:
        return Icons.chat_bubble_outline_rounded;
    }
  }
}

/// One support conversation as the player sees it.
/// Firestore path: `users/{uid}/tickets/{id}` (written by the server only).
class Ticket extends Equatable {
  const Ticket({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.lastFromAgent = false,
    this.lastPreview = '',
    this.unread = false,
    this.messageCount = 0,
  });

  final String id;
  final String subject;
  final TicketCategory category;
  final TicketStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool lastFromAgent;
  final String lastPreview;

  /// A reply from support the player hasn't opened yet.
  final bool unread;
  final int messageCount;

  bool get isClosed => status == TicketStatus.closed;

  factory Ticket.fromFirestore(String id, Json j) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return Ticket(
      id: id,
      subject: parseString(j['subject']) ?? 'Support request',
      category: enumByName(TicketCategory.values, j['category'], TicketCategory.other),
      status: enumByName(TicketStatus.values, j['status'], TicketStatus.open),
      createdAt: parseDate(j['createdAt']) ?? epoch,
      updatedAt: parseDate(j['updatedAt']) ?? parseDate(j['createdAt']) ?? epoch,
      lastFromAgent: j['lastFrom'] == 'agent',
      lastPreview: parseString(j['lastPreview']) ?? '',
      unread: parseBool(j['unread']),
      messageCount: parseInt(j['messageCount']),
    );
  }

  @override
  List<Object?> get props => [id, status, updatedAt, unread, messageCount];
}

/// `users/{uid}/tickets/{tid}/messages/{id}`
class TicketMessage extends Equatable {
  const TicketMessage({required this.id, required this.fromAgent, required this.author, required this.text, required this.createdAt, this.attachments = const []});

  final String id;
  final bool fromAgent;
  final String author;
  final String text;
  final DateTime createdAt;
  final List<Attachment> attachments;

  factory TicketMessage.fromFirestore(String id, Json j) => TicketMessage(
        id: id,
        fromAgent: j['from'] == 'agent',
        author: parseString(j['author']) ?? '',
        text: parseString(j['text']) ?? '',
        createdAt: parseDate(j['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        attachments: [
          for (final a in (j['attachments'] is List ? j['attachments'] as List : const []))
            Attachment.fromJson(parseMap(a)),
        ],
      );

  @override
  List<Object?> get props => [id];
}
