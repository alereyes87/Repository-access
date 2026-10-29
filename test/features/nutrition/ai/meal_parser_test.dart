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

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wger/features/nutrition/ai/meal_parser.dart';

http.Response _answer(Map<String, dynamic> body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

Map<String, dynamic> _message(String text, {String stopReason = 'end_turn'}) => {
  'id': 'msg_1',
  'type': 'message',
  'role': 'assistant',
  'stop_reason': stopReason,
  'content': [
    {'type': 'thinking', 'thinking': ''},
    {'type': 'text', 'text': text},
  ],
};

void main() {
  late http.Request sent;

  ClaudeMealParser parserAnswering(http.Response response) => ClaudeMealParser(
    MockClient((request) async {
      sent = request;
      return response;
    }),
    'sk-test',
  );

  test('sends the description with structured output and fallbacks', () async {
    final parser = parserAnswering(
      _answer(
        _message(
          '{"foods":[{"name":"arroz","search_term":"arroz blanco cocido","grams":200},'
          '{"name":"milanesa","search_term":"milanesa de carne","grams":150}]}',
        ),
      ),
    );

    final foods = await parser.parseText('200 g de arroz y una milanesa', languageName: 'Spanish');

    expect(sent.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(sent.headers['x-api-key'], 'sk-test');
    expect(sent.headers['anthropic-version'], '2026-10-21');
    expect(sent.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');

    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], 'claude-opus-5-5');
    expect(body['fallbacks'], 'default');
    expect(body['output_config']['format']['type'], 'json_schema');
    expect(body['system'], contains('Spanish'));
    expect(body['messages'][0]['content'][0]['text'], '200 g de arroz y una milanesa');

    expect(foods, hasLength(2));
    expect(foods[0].searchTerm, 'arroz blanco cocido');
    expect(foods[0].grams, 200);
    expect(foods[1].name, 'milanesa');
  });

  test('sends a photo as a base64 image block', () async {
    final parser = parserAnswering(_answer(_message('{"foods":[]}')));

    final foods = await parser.parsePhoto(
      Uint8List.fromList([1, 2, 3]),
      mediaType: 'image/jpeg',
      languageName: 'English',
    );

    final content = (jsonDecode(sent.body) as Map<String, dynamic>)['messages'][0]['content'];
    expect(content[0]['type'], 'image');
    expect(content[0]['source']['media_type'], 'image/jpeg');
    expect(content[0]['source']['data'], base64Encode([1, 2, 3]));
    expect(foods, isEmpty);
  });

  test('drops foods without weight or search term', () async {
    final parser = parserAnswering(
      _answer(
        _message(
          '{"foods":[{"name":"agua","search_term":"agua","grams":0},'
          '{"name":"?","search_term":" ","grams":10}]}',
        ),
      ),
    );
    expect(await parser.parseText('agua', languageName: 'Spanish'), isEmpty);
  });

  test('maps errors', () async {
    Future<MealParserError?> errorFor(http.Response response) async {
      try {
        await parserAnswering(response).parseText('x', languageName: 'English');
      } on MealParserException catch (e) {
        return e.error;
      }
      return null;
    }

    expect(await errorFor(_answer({'type': 'error'}, 401)), MealParserError.invalidKey);
    expect(await errorFor(_answer({'type': 'error'}, 429)), MealParserError.rateLimited);
    expect(await errorFor(_answer({'type': 'error'}, 500)), MealParserError.unknown);
    expect(
      await errorFor(_answer(_message('', stopReason: 'refusal'))),
      MealParserError.refusal,
    );
    expect(await errorFor(_answer(_message('not json'))), MealParserError.unknown);
  });
}
