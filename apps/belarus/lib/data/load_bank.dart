import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/question_bank.dart';

Future<QuestionBank> loadBank({AssetBundle? bundle}) async =>
    QuestionBank.fromJson(
      jsonDecode(
            await (bundle ?? rootBundle).loadString(
              const bool.fromEnvironment('BY_CONTENT_PREVIEW')
                  ? 'assets/countries/by/preview_catalog.json'
                  : 'assets/countries/by/catalog.json',
            ),
          )
          as Map<String, dynamic>,
    );
