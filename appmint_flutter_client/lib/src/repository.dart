import 'errors.dart';
import 'http.dart';

/// One page of records.
class Page<T> {
  final List<T> items;
  final int total;
  final int page;
  final int pageSize;

  const Page({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  bool get hasMore => page * pageSize < total;
  bool get isEmpty => items.isEmpty;
}

/// Reads and writes over any datatype.
///
/// Appengine does not hand out a fixed set of tables. Every record has a
/// datatype — `sf_product`, `reservation`, `customer`, one of your own — and
/// the same handful of calls work on all of them. That is the part worth
/// understanding first: you are not limited to the datatypes the platform
/// ships with.
///
/// Records come back as plain maps with the fields under `data`. This client
/// does not impose models on you — your app knows its own shapes better than a
/// generic client can.
class AppmintRepository {
  AppmintRepository(this._http);

  final AppmintHttp _http;

  /// Search a datatype.
  ///
  /// [filter] is passed to the server as-is, so it takes the query shape the
  /// backend understands (`{'data.status': 'active'}`, and operators like
  /// `{'data.total': {r'$gt': 100}}`).
  Future<Page<Map<String, dynamic>>> find(
    String datatype, {
    Map<String, dynamic>? filter,
    int page = 1,
    int pageSize = 50,
    Map<String, dynamic>? sort,
  }) async {
    final res = await _http.post('/repository/find/$datatype', body: {
      'filter': filter ?? <String, dynamic>{},
      'page': page,
      'pageSize': pageSize,
      if (sort != null) 'sort': sort,
    });

    final map = res is Map ? Map<String, dynamic>.from(res) : const {};
    final raw = (map['data'] ?? map['items'] ?? res);
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    return Page(
      items: items,
      total: (map['total'] as num?)?.toInt() ?? items.length,
      page: page,
      pageSize: pageSize,
    );
  }

  /// One record by id.
  Future<Map<String, dynamic>?> findById(String datatype, String id) async {
    final res = await _http.get('/repository/findone/$datatype/$id');
    return res is Map ? Map<String, dynamic>.from(res) : null;
  }

  /// Look a record up by one attribute.
  ///
  /// > Matching here is **loose**, not exact: a value can bring back records
  /// > that merely resemble it. Read what comes back and confirm each record is
  /// > the one you meant before acting on it — and never feed the results
  /// > straight into [delete]. That mistake has destroyed live records.
  Future<List<Map<String, dynamic>>> findByAttribute(
    String datatype,
    String attribute,
    String value,
  ) async {
    final res = await _http
        .get('/repository/find-by-attribute/$datatype/$attribute/$value');
    final raw = res is Map ? (res['data'] ?? res['items']) : res;
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
  }

  /// Create a record.
  ///
  /// Note this is a PUT on the server, not a POST — an inconsistency you would
  /// otherwise discover through a 404.
  Future<Map<String, dynamic>> create(
    String datatype,
    Map<String, dynamic> data,
  ) async {
    final res = await _http.put('/repository/create', body: {
      'datatype': datatype,
      // Without this the server answers "Not a new metrics, please use update
      // or set the new property" — a sentence that says nothing about what is
      // missing. The client sends it so nobody has to learn that the hard way.
      'isNew': true,
      'data': data,
    });
    if (res is Map && res.isNotEmpty) return Map<String, dynamic>.from(res);
    // The server keeps the last create it saw and answers an exact repeat of
    // it with 200 and no body — a guard against double-taps, not an error in
    // its eyes. Returning `{}` here made callers show a blank row. Say it.
    throw AppmintException(
      'The server ignored this create because it was identical to the one '
      'before it. Change something in the record before sending it again.',
      statusCode: 200,
      reason: 'duplicate_create',
    );
  }

  /// Replace a record.
  Future<Map<String, dynamic>> update(
    String datatype,
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await _http.post('/repository/update/$datatype/$id', body: {
      'data': data,
    });
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  /// Change named fields, leaving the rest of the record alone.
  ///
  /// Keys are dot paths into the record, not a nested object:
  /// `{'data.status': 'active', 'data.settings.theme': 'dark'}`. Passing a
  /// nested map instead replaces the whole branch, which is rarely what anyone
  /// wants and fails quietly.
  Future<Map<String, dynamic>> updateFields(
    String datatype,
    String id,
    Map<String, dynamic> dotPathValues,
  ) async {
    final res = await _http.post(
      '/repository/update-partial/$datatype/$id',
      body: dotPathValues,
    );
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  /// Delete a record by id.
  ///
  /// Read the record first if you found it by search — see [findByAttribute].
  Future<void> delete(String datatype, String id) async {
    await _http.delete('/repository/delete/$datatype/$id');
  }
}
