import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/question_bank.dart';

Future<QuestionBank> loadBank({AssetBundle? bundle}) async =>
    QuestionBank.fromJson(
      jsonDecode(
            await (bundle ?? rootBundle).loadString(
              'assets/countries/by/catalog.json',
            ),
          )
          as Map<String, dynamic>,
    );
