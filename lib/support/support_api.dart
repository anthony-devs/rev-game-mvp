import 'dart:typed_data';

import '../core/api/api_client.dart';
import '../model/model_json.dart';
import 'support_models.dart';

/// Attachments and support tickets. Writes go through the game server
/// (it checks everything); the app reads tickets live from Firestore.
class SupportApi {
  SupportApi(this._api);

  final ApiClient _api;

  /// Same limits as the server.
  static const int maxFiles = 5;
  static const int maxMb = 25;

  /// Uploads one photo, video or PDF. Works even when the account is restricted.
  Future<Attachment> upload(String path, String name) async =>
      Attachment.fromJson(await _api.upload('/v1/uploads', path, filename: name));

  Future<Uint8List> download(String fileId) => _api.getBytes('/v1/uploads/$fileId');

  /// Returns the new ticket's id.
  Future<String> createTicket({required TicketCategory category, required String subject, required String message, List<String> attachments = const []}) async {
    final j = await _api.post('/v1/support/tickets', {
      'category': category.name,
      'subject': subject,
      'message': message,
      'attachments': attachments,
    });
    return parseString(j['id']) ?? '';
  }

  Future<void> reply(String ticketId, String message, List<String> attachments) async {
    await _api.post('/v1/support/tickets/$ticketId/messages', {'message': message, 'attachments': attachments});
  }

  Future<void> markRead(String ticketId) async {
    await _api.post('/v1/support/tickets/$ticketId/read');
  }

  Future<void> close(String ticketId) async {
    await _api.post('/v1/support/tickets/$ticketId/close');
  }
}
