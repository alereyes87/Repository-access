/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2020 - 2026 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// One food Claude found in a description or photo of a meal
class ParsedFood {
  /// Name as the user would say it, e.g. "milanesa de carne"
  final String name;

  /// Short generic term to look the food up in the ingredient database
  final String searchTerm;

  /// Estimated weight of the edible portion
  final num grams;

  const ParsedFood({required this.name, required this.searchTerm, required this.grams});

  factory ParsedFood.fromJson(Map<String, dynamic> json) => ParsedFood(
    name: json['name'] as String,
    searchTerm: json['search_term'] as String,
    grams: json['grams'] as num,
  );
}

enum MealParserError { invalidKey, rateLimited, refusal, network, unknown }

class MealParserException implements Exception {
  final MealParserError error;
  final String? detail;

  const MealParserException(this.error, [this.detail]);

  @override
  String toString() => 'MealParserException($error, $detail)';
}

/// Turns a free-text description or a photo of a meal into foods and grams,
/// with the Claude API. Dart has no official Anthropic SDK, so this talks to
/// the Messages endpoint over plain HTTP.
class ClaudeMealParser {
  static const endpoint = 'https://api.anthropic.com/v1/messages';
  static const model = 'claude-opus-5-5';

  static const _schema = {
    'type': 'object',
    'properties': {
      'foods': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'search_term': {'type': 'string'},
            'grams': {'type': 'number'},
          },
          'required': ['name', 'search_term', 'grams'],
          'additionalProperties': false,
        },
      },
    },
    'required': ['foods'],
    'additionalProperties': false,
  };

  final http.Client _client;
  final String apiKey;

  ClaudeMealParser(this._client, this.apiKey);

  static String systemPrompt(String languageName) =>
      'You help people log what they ate in a nutrition diary. From the description or '
      'photo of a meal, list every food in it separately, with the weight of the edible '
      'portion in grams. Use the weights the person gives; estimate the rest from usual '
      'portion sizes, or from what you see in the photo. For each food give its name as '
      'the person would say it, and a short generic search term in $languageName for a '
      'food database (for example "arroz blanco cocido" rather than a brand or a dish '
      'name). Split dishes into their main ingredients only when the database would not '
      'have the dish itself. If there is no food, return an empty list.';

  Future<List<ParsedFood>> parseText(String description, {required String languageName}) => _send([
    {'type': 'text', 'text': description},
  ], languageName);

  Future<List<ParsedFood>> parsePhoto(
    Uint8List bytes, {
    required String mediaType,
    String? note,
    required String languageName,
  }) => _send([
    {
      'type': 'image',
      'source': {'type': 'base64', 'media_type': mediaType, 'data': base64Encode(bytes)},
    },
    {'type': 'text', 'text': (note == null || note.isEmpty) ? 'What did I eat?' : note},
  ], languageName);

  /// The request body, separate for the tests
  static Map<String, dynamic> requestBody(
    List<Map<String, dynamic>> content,
    String languageName,
  ) => {
    'model': model,
    'max_tokens': 16000,
    'fallbacks': 'default',
    'output_config': {
      'effort': 'low',
      'format': {'type': 'json_schema', 'schema': _schema},
    },
    'system': systemPrompt(languageName),
    'messages': [
      {'role': 'user', 'content': content},
    ],
  };

  Future<List<ParsedFood>> _send(List<Map<String, dynamic>> content, String languageName) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse(endpoint),
        headers: {
          'content-type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2026-10-21',
          'anthropic-beta': 'server-side-fallback-2026-07-01',
        },
        body: jsonEncode(requestBody(content, languageName)),
      );
    } on http.ClientException catch (e) {
      throw MealParserException(MealParserError.network, e.message);
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 401 || 403:
        throw MealParserException(MealParserError.invalidKey, response.body);
      case 429 || 529:
        throw MealParserException(MealParserError.rateLimited, response.body);
      default:
        throw MealParserException(MealParserError.unknown, response.body);
    }

    final message = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (message['stop_reason'] == 'refusal') {
      throw const MealParserException(MealParserError.refusal);
    }
    final text = (message['content'] as List)
        .cast<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      return (data['foods'] as List)
          .map((f) => ParsedFood.fromJson(f as Map<String, dynamic>))
          .where((f) => f.grams > 0 && f.searchTerm.trim().isNotEmpty)
          .toList();
    } on FormatException catch (e) {
      throw MealParserException(MealParserError.unknown, e.message);
    }
  }
}

const SECURE_STORAGE_ANTHROPIC_KEY = 'anthropicApiKey';

/// The user's own Anthropic API key, kept in the platform's secure storage
class AnthropicKeyNotifier extends AsyncNotifier<String?> {
  FlutterSecureStorage get _storage => ref.read(anthropicKeyStorageProvider);

  @override
  Future<String?> build() async {
    final key = await _storage.read(key: SECURE_STORAGE_ANTHROPIC_KEY);
    return (key == null || key.isEmpty) ? null : key;
  }

  Future<void> setKey(String? key) async {
    final value = key?.trim();
    if (value == null || value.isEmpty) {
      await _storage.delete(key: SECURE_STORAGE_ANTHROPIC_KEY);
      state = const AsyncData(null);
    } else {
      await _storage.write(key: SECURE_STORAGE_ANTHROPIC_KEY, value: value);
      state = AsyncData(value);
    }
  }
}

final anthropicKeyStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final anthropicKeyProvider = AsyncNotifierProvider<AnthropicKeyNotifier, String?>(
  AnthropicKeyNotifier.new,
);

final mealParserHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
