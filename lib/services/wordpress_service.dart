import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/article.dart';
import '../models/news_source.dart';
import 'feed_parsers.dart';

class FeedException implements Exception {
  const FeedException(this.message, {this.isOffline = false});

  final String message;
  final bool isOffline;

  @override
  String toString() => message;
}

/// Reads posts from WordPress sites: through the REST API where a site allows
/// it, through the site's RSS feed where it does not (see [FeedKind]).
class WordPressService {
  WordPressService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  final Map<String, int> _termIds = {};

  /// One page of [source]'s newest posts (page 1 = newest). An empty list means
  /// the page is beyond the last one. Throws [FeedException].
  Future<List<Article>> fetchPosts(NewsSource source, {int page = 1}) =>
      switch (source.kind) {
        FeedKind.wpRest => _fetchRest(source, page),
        FeedKind.rss => _fetchRss(source, page),
      };

  Future<List<Article>> _fetchRest(NewsSource source, int page) async {
    final topic = source.topic;
    final topicId = topic == null ? null : await _termId(source, topic);

    final body = await _get(
      source,
      '/wp-json/wp/v2/posts',
      {
        if (page > 1) 'page': '$page',
        'per_page': '${source.pageSize}',
        // Newest first is WordPress' default, but wccftech ignores a custom
        // taxonomy filter (`topics=`) unless `orderby` is sent as well.
        'orderby': 'date',
        '_embed': 'wp:featuredmedia,wp:term',
        '_fields':
            'id,date_gmt,link,title,content,featured_media,_links,_embedded',
        if (topic != null) topic.restBase: '$topicId',
      },
      // WordPress answers HTTP 400 when `page` is past the last page.
      pastTheEnd: page > 1 ? 400 : null,
    );
    if (body == null) return const [];

    final ParsedPosts parsed;
    try {
      parsed = await compute(_parsePostsMessage, (source, body));
    } on FormatException {
      throw _unexpected();
    }
    if (parsed.pendingMedia.isEmpty) return parsed.articles;

    final images = await _featuredImages(source, parsed.pendingMedia.values);
    return [
      for (final article in parsed.articles)
        if (images[parsed.pendingMedia[article.id]] case final url?)
          article.withImage(url)
        else
          article,
    ];
  }

  Future<List<Article>> _fetchRss(NewsSource source, int page) async {
    final body = await _get(
      source,
      '/feed/',
      {if (page > 1) 'paged': '$page'},
      accept: 'application/rss+xml, application/xml;q=0.9',
      // WordPress answers HTTP 404 when `paged` is past the last page.
      pastTheEnd: page > 1 ? 404 : null,
    );
    if (body == null) return const [];

    try {
      return await compute(_parseFeedMessage, (source, body));
    } on FormatException {
      throw _unexpected();
    }
  }

  /// Featured images for sites that ignore `_embed`, in one request. Images are
  /// an enhancement, so a failure here leaves the posts with their body image
  /// instead of failing the whole page.
  Future<Map<int, String>> _featuredImages(
    NewsSource source,
    Iterable<int> mediaIds,
  ) async {
    try {
      final body = await _get(source, '/wp-json/wp/v2/media', {
        'include': mediaIds.join(','),
        'per_page': '${mediaIds.length}',
        '_fields': 'id,source_url,media_details',
      });
      return body == null ? const {} : parseMedia(body);
    } on FeedException {
      return const {};
    } on FormatException {
      return const {};
    }
  }

  /// Resolves a taxonomy term slug to its numeric id (the posts endpoint only
  /// filters by id). Cached for the lifetime of the service.
  Future<int> _termId(NewsSource source, TermFilter term) async {
    final key = '${source.name}/${term.restBase}/${term.slug}';
    final cached = _termIds[key];
    if (cached != null) return cached;

    final body = await _get(source, '/wp-json/wp/v2/${term.restBase}', {
      'slug': term.slug,
      '_fields': 'id,slug',
    });
    try {
      final decoded = jsonDecode(body!);
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        final id = (decoded.first as Map)['id'];
        if (id is int) return _termIds[key] = id;
      }
    } on FormatException {
      throw _unexpected();
    }
    throw const FeedException('A news source is missing an expected feed.');
  }

  /// Returns the response body, or null when the status is [pastTheEnd].
  Future<String?> _get(
    NewsSource source,
    String path,
    Map<String, String> query, {
    String accept = 'application/json',
    int? pastTheEnd,
  }) async {
    final uri = Uri.parse(
      source.baseUrl,
    ).replace(path: path, queryParameters: query.isEmpty ? null : query);

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'Accept': accept})
          .timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw const FeedException(
        'The request timed out. Check your connection.',
        isOffline: true,
      );
    } on SocketException {
      throw const FeedException(
        "You're offline. Check your connection.",
        isOffline: true,
      );
    } on http.ClientException {
      throw const FeedException(
        "You're offline. Check your connection.",
        isOffline: true,
      );
    }

    if (response.statusCode == pastTheEnd) return null;
    if (response.statusCode != 200) {
      throw FeedException(
        'A news source returned an error (HTTP ${response.statusCode}).',
      );
    }
    return utf8.decode(response.bodyBytes);
  }

  FeedException _unexpected() =>
      const FeedException('A news source sent an unexpected response.');

  void dispose() => _client.close();
}

ParsedPosts _parsePostsMessage((NewsSource, String) message) =>
    parsePosts(message.$1, message.$2);

List<Article> _parseFeedMessage((NewsSource, String) message) =>
    parseFeed(message.$1, message.$2);
