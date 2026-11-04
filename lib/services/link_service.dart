import '../core/currencies.dart';
import '../data/models.dart' show toD;
import 'db_service.dart';

/// Hub linking — the idea that makes DailyHub a "hub" rather than ten
/// separate lists. Any record can be linked to any other, so a trip carries
/// its notes, expenses and tasks with it.
///
/// Links are stored on the record itself as a list of {collection, id} maps,
/// and written to BOTH sides so the connection is visible from either end.
class LinkService {
  LinkService._();
  static final LinkService instance = LinkService._();

  final _db = DbService.instance;

  /// Collections that can take part in linking, with display labels.
  static const linkable = {
    'trips': 'Trip',
    'todos': 'Task',
    'notes': 'Note',
    'txns': 'Money entry',
    'reminders': 'Reminder',
    'bookmarks': 'Bookmark',
    'meetings': 'Meeting',
  };

  /// Collections that live under the shared workspace rather than personal.
  static bool isWorkspace(String collection) =>
      collection == 'trips' || collection == 'todos';

  static List<Map<String, dynamic>> linksOf(Map<String, dynamic> item) {
    final raw = item['links'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  /// Connect two records. Writes the link on both records.
  Future<void> link({
    required String fromCollection,
    required String fromId,
    required Map<String, dynamic> fromData,
    required String toCollection,
    required String toId,
    required Map<String, dynamic> toData,
  }) async {
    final fromLinks = linksOf(fromData);
    if (!fromLinks.any((l) =>
        l['collection'] == toCollection && l['id'] == toId)) {
      fromLinks.add({'collection': toCollection, 'id': toId});
      await _db.update(fromCollection, fromId, {'links': fromLinks},
          workspace: isWorkspace(fromCollection));
    }

    final toLinks = linksOf(toData);
    if (!toLinks.any((l) =>
        l['collection'] == fromCollection && l['id'] == fromId)) {
      toLinks.add({'collection': fromCollection, 'id': fromId});
      await _db.update(toCollection, toId, {'links': toLinks},
          workspace: isWorkspace(toCollection));
    }
  }

  /// Remove a link from both sides.
  Future<void> unlink({
    required String fromCollection,
    required String fromId,
    required Map<String, dynamic> fromData,
    required String toCollection,
    required String toId,
  }) async {
    final fromLinks = linksOf(fromData)
      ..removeWhere(
          (l) => l['collection'] == toCollection && l['id'] == toId);
    await _db.update(fromCollection, fromId, {'links': fromLinks},
        workspace: isWorkspace(fromCollection));

    // Read the other side fresh so we don't overwrite its other links.
    final others = await _db
        .stream(toCollection, workspace: isWorkspace(toCollection))
        .first;
    final other = others.firstWhere((e) => e['id'] == toId,
        orElse: () => <String, dynamic>{});
    if (other.isEmpty) return;
    final toLinks = linksOf(other)
      ..removeWhere(
          (l) => l['collection'] == fromCollection && l['id'] == fromId);
    await _db.update(toCollection, toId, {'links': toLinks},
        workspace: isWorkspace(toCollection));
  }

  /// Resolve a record's links into the actual records they point at.
  Future<List<({String collection, Map<String, dynamic> data})>> resolve(
      Map<String, dynamic> item) async {
    final links = linksOf(item);
    final out = <({String collection, Map<String, dynamic> data})>[];
    // Group by collection so each one is fetched once, not per link.
    final byCollection = <String, List<String>>{};
    for (final l in links) {
      final c = l['collection']?.toString();
      final id = l['id']?.toString();
      if (c == null || id == null) continue;
      byCollection.putIfAbsent(c, () => []).add(id);
    }
    for (final entry in byCollection.entries) {
      try {
        final all = await _db
            .stream(entry.key, workspace: isWorkspace(entry.key))
            .first;
        for (final id in entry.value) {
          final match = all.firstWhere((e) => e['id'] == id,
              orElse: () => <String, dynamic>{});
          if (match.isNotEmpty) {
            out.add((collection: entry.key, data: match));
          }
        }
      } catch (_) {
        // A collection that can't be read is skipped rather than failing
        // the whole resolve.
      }
    }
    return out;
  }

  /// Short display title for any record, whatever collection it's from.
  static String titleOf(String collection, Map<String, dynamic> d) {
    return switch (collection) {
      'trips' => '${d['from'] ?? ''} → ${d['to'] ?? ''}',
      'txns' => (d['note'] ?? '').toString().isNotEmpty
          ? d['note'].toString()
          : Money.format(toD(d['amount'])),
      'notes' => (d['title'] ?? '').toString().isNotEmpty
          ? d['title'].toString()
          : (d['body'] ?? 'Note').toString(),
      _ => (d['title'] ?? d['name'] ?? 'Item').toString(),
    };
  }
}
