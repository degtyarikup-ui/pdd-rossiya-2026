import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/reel_item.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReelsRepository {
  static const String _keyLikedIds = 'reels_liked_ids';
  static const String _keySavedIds = 'reels_saved_ids';
  static const String _keySharesPrefix = 'reels_shares_';
  static const String _keyCachePrefix = 'reels_cache_';

  /// 58 встроенных видеороликов (Билеты и Знаки чередуются друг за другом)
  static final List<ReelItem> _fallbackReels = [
    ReelItem(
      id: 'reel_pdd1_01_02_bilet01_mozhno-li-vam-ostanovitsya',
      title: 'Билет 1, Вопрос 3',
      description: '',
      videoUrl: 'assets/videos/02_bilet01_mozhno-li-vam-ostanovitsya.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 3,
      likesCount: 15,
      savesCount: 4,
      sharesCount: 2,
      createdAt: DateTime.parse('2026-08-20T10:00:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_01_02_zapreshchayushchie_1',
      title: 'Запрещающие знаки',
      description: '',
      videoUrl: 'assets/videos/02_zapreshchayushchie_1.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Запрещающие знаки',
      likesCount: 20,
      savesCount: 6,
      sharesCount: 3,
      createdAt: DateTime.parse('2026-08-20T11:00:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_02_03_bilet02_mozhno-li-vam-vypolnit',
      title: 'Билет 2, Вопрос 9',
      description: '',
      videoUrl: 'assets/videos/03_bilet02_mozhno-li-vam-vypolnit.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 9,
      likesCount: 22,
      savesCount: 7,
      sharesCount: 7,
      createdAt: DateTime.parse('2026-08-20T10:01:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_02_03_osobyh-predpisaniy_1',
      title: 'Знаки особых предписаний',
      description: '',
      videoUrl: 'assets/videos/03_osobyh-predpisaniy_1.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Знаки особых предписаний',
      likesCount: 29,
      savesCount: 10,
      sharesCount: 9,
      createdAt: DateTime.parse('2026-08-20T11:01:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_03_04_bilet03_kto-iz-voditeley-narushil',
      title: 'Билет 3, Вопрос 12',
      description: '',
      videoUrl: 'assets/videos/04_bilet03_kto-iz-voditeley-narushil.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 3,
      targetQuestion: 12,
      likesCount: 29,
      savesCount: 10,
      sharesCount: 12,
      createdAt: DateTime.parse('2026-08-20T10:02:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_03_04_servisa_1',
      title: 'Знаки сервиса',
      description: '',
      videoUrl: 'assets/videos/04_servisa_1.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Знаки сервиса',
      likesCount: 38,
      savesCount: 14,
      sharesCount: 15,
      createdAt: DateTime.parse('2026-08-20T11:02:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_04_05_bilet02_skolko-polos-dlya-dvizheniya',
      title: 'Билет 2, Вопрос 1',
      description: '',
      videoUrl: 'assets/videos/05_bilet02_skolko-polos-dlya-dvizheniya.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 1,
      likesCount: 36,
      savesCount: 13,
      sharesCount: 17,
      createdAt: DateTime.parse('2026-08-20T10:03:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_04_05_predpisyvayushchie_1',
      title: 'Предписывающие знаки',
      description: '',
      videoUrl: 'assets/videos/05_predpisyvayushchie_1.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Предписывающие знаки',
      likesCount: 47,
      savesCount: 18,
      sharesCount: 21,
      createdAt: DateTime.parse('2026-08-20T11:03:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_05_06_bilet01_razreshen-li-vam-povorot',
      title: 'Билет 1, Вопрос 2',
      description: '',
      videoUrl: 'assets/videos/06_bilet01_razreshen-li-vam-povorot.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 2,
      likesCount: 43,
      savesCount: 16,
      sharesCount: 22,
      createdAt: DateTime.parse('2026-08-20T10:04:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_05_06_informacionnye_1',
      title: 'Информационные знаки',
      description: '',
      videoUrl: 'assets/videos/06_informacionnye_1.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Информационные знаки',
      likesCount: 56,
      savesCount: 22,
      sharesCount: 27,
      createdAt: DateTime.parse('2026-08-20T11:04:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_06_07_bilet01_vy-namereny-proehat-perekrestok',
      title: 'Билет 1, Вопрос 14',
      description: '',
      videoUrl: 'assets/videos/07_bilet01_vy-namereny-proehat-perekrestok.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 14,
      likesCount: 50,
      savesCount: 19,
      sharesCount: 2,
      createdAt: DateTime.parse('2026-08-20T10:05:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_06_07_prioriteta_1',
      title: 'Знаки приоритета',
      description: '',
      videoUrl: 'assets/videos/07_prioriteta_1.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Знаки приоритета',
      likesCount: 65,
      savesCount: 26,
      sharesCount: 3,
      createdAt: DateTime.parse('2026-08-20T11:05:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_07_08_bilet01_s-kakoy-skorostyu-vy',
      title: 'Билет 1, Вопрос 10',
      description: '',
      videoUrl: 'assets/videos/08_bilet01_s-kakoy-skorostyu-vy.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 10,
      likesCount: 57,
      savesCount: 22,
      sharesCount: 7,
      createdAt: DateTime.parse('2026-08-20T10:06:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_07_08_preduprezhdayushchie_2',
      title: 'Предупреждающие знаки',
      description: '',
      videoUrl: 'assets/videos/08_preduprezhdayushchie_2.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Предупреждающие знаки',
      likesCount: 74,
      savesCount: 30,
      sharesCount: 9,
      createdAt: DateTime.parse('2026-08-20T11:06:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_08_09_bilet01_kak-vam-sleduet-postupit',
      title: 'Билет 1, Вопрос 8',
      description: '',
      videoUrl: 'assets/videos/09_bilet01_kak-vam-sleduet-postupit.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 8,
      likesCount: 64,
      savesCount: 25,
      sharesCount: 12,
      createdAt: DateTime.parse('2026-08-20T10:07:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_08_09_zapreshchayushchie_2',
      title: 'Запрещающие знаки',
      description: '',
      videoUrl: 'assets/videos/09_zapreshchayushchie_2.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Запрещающие знаки',
      likesCount: 83,
      savesCount: 34,
      sharesCount: 15,
      createdAt: DateTime.parse('2026-08-20T11:07:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_09_10_bilet01_v-kakom-sluchae-voditelyu',
      title: 'Билет 1, Вопрос 1',
      description: '',
      videoUrl: 'assets/videos/10_bilet01_v-kakom-sluchae-voditelyu.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 1,
      likesCount: 71,
      savesCount: 28,
      sharesCount: 17,
      createdAt: DateTime.parse('2026-08-20T10:08:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_09_10_osobyh-predpisaniy_2',
      title: 'Знаки особых предписаний',
      description: '',
      videoUrl: 'assets/videos/10_osobyh-predpisaniy_2.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Знаки особых предписаний',
      likesCount: 92,
      savesCount: 38,
      sharesCount: 21,
      createdAt: DateTime.parse('2026-08-20T11:08:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_10_11_bilet01_po-kakoy-traektorii-vam',
      title: 'Билет 1, Вопрос 9',
      description: '',
      videoUrl: 'assets/videos/11_bilet01_po-kakoy-traektorii-vam.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 9,
      likesCount: 78,
      savesCount: 31,
      sharesCount: 22,
      createdAt: DateTime.parse('2026-08-20T10:09:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_10_11_servisa_2',
      title: 'Знаки сервиса',
      description: '',
      videoUrl: 'assets/videos/11_servisa_2.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Знаки сервиса',
      likesCount: 101,
      savesCount: 7,
      sharesCount: 27,
      createdAt: DateTime.parse('2026-08-20T11:09:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_11_12_bilet01_s-kakoy-maksimalnoy-skorostyu',
      title: 'Билет 1, Вопрос 16',
      description: '',
      videoUrl: 'assets/videos/12_bilet01_s-kakoy-maksimalnoy-skorostyu.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 16,
      likesCount: 85,
      savesCount: 4,
      sharesCount: 2,
      createdAt: DateTime.parse('2026-08-20T10:10:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_11_12_predpisyvayushchie_2',
      title: 'Предписывающие знаки',
      description: '',
      videoUrl: 'assets/videos/12_predpisyvayushchie_2.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Предписывающие знаки',
      likesCount: 110,
      savesCount: 11,
      sharesCount: 3,
      createdAt: DateTime.parse('2026-08-20T11:10:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_12_13_bilet01_vy-namereny-povernut-nalevo',
      title: 'Билет 1, Вопрос 5',
      description: '',
      videoUrl: 'assets/videos/13_bilet01_vy-namereny-povernut-nalevo.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 5,
      likesCount: 92,
      savesCount: 7,
      sharesCount: 7,
      createdAt: DateTime.parse('2026-08-20T10:11:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_12_13_informacionnye_2',
      title: 'Информационные знаки',
      description: '',
      videoUrl: 'assets/videos/13_informacionnye_2.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Информационные знаки',
      likesCount: 24,
      savesCount: 15,
      sharesCount: 9,
      createdAt: DateTime.parse('2026-08-20T11:11:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_13_14_bilet01_mozhno-li-voditelyu-legkovogo',
      title: 'Билет 1, Вопрос 11',
      description: '',
      videoUrl: 'assets/videos/14_bilet01_mozhno-li-voditelyu-legkovogo.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 11,
      likesCount: 99,
      savesCount: 10,
      sharesCount: 12,
      createdAt: DateTime.parse('2026-08-20T10:12:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_13_14_preduprezhdayushchie_3',
      title: 'Предупреждающие знаки',
      description: '',
      videoUrl: 'assets/videos/14_preduprezhdayushchie_3.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Предупреждающие знаки',
      likesCount: 33,
      savesCount: 19,
      sharesCount: 15,
      createdAt: DateTime.parse('2026-08-20T11:12:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_14_15_bilet01_komu-vy-obyazany-ustupit',
      title: 'Билет 1, Вопрос 15',
      description: '',
      videoUrl: 'assets/videos/15_bilet01_komu-vy-obyazany-ustupit.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 15,
      likesCount: 21,
      savesCount: 13,
      sharesCount: 17,
      createdAt: DateTime.parse('2026-08-20T10:13:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_14_15_zapreshchayushchie_3',
      title: 'Запрещающие знаки',
      description: '',
      videoUrl: 'assets/videos/15_zapreshchayushchie_3.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Запрещающие знаки',
      likesCount: 42,
      savesCount: 23,
      sharesCount: 21,
      createdAt: DateTime.parse('2026-08-20T11:13:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_15_16_bilet01_pri-povorote-napravo-vy',
      title: 'Билет 1, Вопрос 8',
      description: '',
      videoUrl: 'assets/videos/16_bilet01_pri-povorote-napravo-vy.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 8,
      likesCount: 28,
      savesCount: 16,
      sharesCount: 22,
      createdAt: DateTime.parse('2026-08-20T10:14:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_15_16_preduprezhdayushchie_4',
      title: 'Предупреждающие знаки',
      description: '',
      videoUrl: 'assets/videos/16_preduprezhdayushchie_4.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Предупреждающие знаки',
      likesCount: 51,
      savesCount: 27,
      sharesCount: 27,
      createdAt: DateTime.parse('2026-08-20T11:14:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_16_17_bilet01_kakie-iz-ukazannyh-znakov',
      title: 'Билет 1, Вопрос 4',
      description: '',
      videoUrl: 'assets/videos/17_bilet01_kakie-iz-ukazannyh-znakov.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 1,
      targetQuestion: 4,
      likesCount: 35,
      savesCount: 19,
      sharesCount: 2,
      createdAt: DateTime.parse('2026-08-20T10:15:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_16_17_osobyh-predpisaniy_3',
      title: 'Знаки особых предписаний',
      description: '',
      videoUrl: 'assets/videos/17_osobyh-predpisaniy_3.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Знаки особых предписаний',
      likesCount: 60,
      savesCount: 31,
      sharesCount: 3,
      createdAt: DateTime.parse('2026-08-20T11:15:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_17_18_bilet02_razreshaetsya-li-voditelyu-vypolnit',
      title: 'Билет 2, Вопрос 16',
      description: '',
      videoUrl: 'assets/videos/18_bilet02_razreshaetsya-li-voditelyu-vypolnit.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 16,
      likesCount: 42,
      savesCount: 22,
      sharesCount: 7,
      createdAt: DateTime.parse('2026-08-20T10:16:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_17_18_servisa_3',
      title: 'Знаки сервиса',
      description: '',
      videoUrl: 'assets/videos/18_servisa_3.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Знаки сервиса',
      likesCount: 69,
      savesCount: 35,
      sharesCount: 9,
      createdAt: DateTime.parse('2026-08-20T11:16:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_18_19_bilet02_dvigayas-po-levoy-polose',
      title: 'Билет 2, Вопрос 1',
      description: '',
      videoUrl: 'assets/videos/19_bilet02_dvigayas-po-levoy-polose.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 1,
      likesCount: 49,
      savesCount: 25,
      sharesCount: 12,
      createdAt: DateTime.parse('2026-08-20T10:17:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_18_19_predpisyvayushchie_3',
      title: 'Предписывающие знаки',
      description: '',
      videoUrl: 'assets/videos/19_predpisyvayushchie_3.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Предписывающие знаки',
      likesCount: 78,
      savesCount: 39,
      sharesCount: 15,
      createdAt: DateTime.parse('2026-08-20T11:17:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_19_20_bilet02_podnyataya-vverh-ruka-voditelya',
      title: 'Билет 2, Вопрос 7',
      description: '',
      videoUrl: 'assets/videos/20_bilet02_podnyataya-vverh-ruka-voditelya.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 7,
      likesCount: 56,
      savesCount: 28,
      sharesCount: 17,
      createdAt: DateTime.parse('2026-08-20T10:18:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_19_20_informacionnye_3',
      title: 'Информационные знаки',
      description: '',
      videoUrl: 'assets/videos/20_informacionnye_3.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Информационные знаки',
      likesCount: 87,
      savesCount: 8,
      sharesCount: 21,
      createdAt: DateTime.parse('2026-08-20T11:18:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_20_21_bilet02_razresheno-li-vam-proizvesti',
      title: 'Билет 2, Вопрос 3',
      description: '',
      videoUrl: 'assets/videos/21_bilet02_razresheno-li-vam-proizvesti.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 3,
      likesCount: 63,
      savesCount: 31,
      sharesCount: 22,
      createdAt: DateTime.parse('2026-08-20T10:19:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_20_21_zapreshchayushchie_4',
      title: 'Запрещающие знаки',
      description: '',
      videoUrl: 'assets/videos/21_zapreshchayushchie_4.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Запрещающие знаки',
      likesCount: 96,
      savesCount: 12,
      sharesCount: 27,
      createdAt: DateTime.parse('2026-08-20T11:19:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_21_22_bilet02_vy-namereny-povernut-nalevo',
      title: 'Билет 2, Вопрос 13',
      description: '',
      videoUrl: 'assets/videos/22_bilet02_vy-namereny-povernut-nalevo.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 13,
      likesCount: 70,
      savesCount: 4,
      sharesCount: 2,
      createdAt: DateTime.parse('2026-08-20T10:20:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_21_22_preduprezhdayushchie_5',
      title: 'Предупреждающие знаки',
      description: '',
      videoUrl: 'assets/videos/22_preduprezhdayushchie_5.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Предупреждающие знаки',
      likesCount: 105,
      savesCount: 16,
      sharesCount: 3,
      createdAt: DateTime.parse('2026-08-20T11:20:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_22_23_bilet02_obyazan-li-voditel-motocikla',
      title: 'Билет 2, Вопрос 15',
      description: '',
      videoUrl: 'assets/videos/23_bilet02_obyazan-li-voditel-motocikla.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 15,
      likesCount: 77,
      savesCount: 7,
      sharesCount: 7,
      createdAt: DateTime.parse('2026-08-20T10:21:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_22_23_zapreshchayushchie_5',
      title: 'Запрещающие знаки',
      description: '',
      videoUrl: 'assets/videos/23_zapreshchayushchie_5.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Запрещающие знаки',
      likesCount: 114,
      savesCount: 20,
      sharesCount: 9,
      createdAt: DateTime.parse('2026-08-20T11:21:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_23_24_bilet02_v-kakom-sluchae-vy',
      title: 'Билет 2, Вопрос 10',
      description: '',
      videoUrl: 'assets/videos/24_bilet02_v-kakom-sluchae-vy.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 10,
      likesCount: 84,
      savesCount: 10,
      sharesCount: 12,
      createdAt: DateTime.parse('2026-08-20T10:22:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_23_24_osobyh-predpisaniy_4',
      title: 'Знаки особых предписаний',
      description: '',
      videoUrl: 'assets/videos/24_osobyh-predpisaniy_4.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Знаки особых предписаний',
      likesCount: 28,
      savesCount: 24,
      sharesCount: 15,
      createdAt: DateTime.parse('2026-08-20T11:22:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_24_25_bilet02_chto-zaprescheno-v-zone',
      title: 'Билет 2, Вопрос 4',
      description: '',
      videoUrl: 'assets/videos/25_bilet02_chto-zaprescheno-v-zone.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 4,
      likesCount: 91,
      savesCount: 13,
      sharesCount: 17,
      createdAt: DateTime.parse('2026-08-20T10:23:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_24_25_servisa_4',
      title: 'Знаки сервиса',
      description: '',
      videoUrl: 'assets/videos/25_servisa_4.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Знаки сервиса',
      likesCount: 37,
      savesCount: 28,
      sharesCount: 21,
      createdAt: DateTime.parse('2026-08-20T11:23:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_25_26_bilet02_razreshen-li-vam-vyezd',
      title: 'Билет 2, Вопрос 3',
      description: '',
      videoUrl: 'assets/videos/26_bilet02_razreshen-li-vam-vyezd.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 3,
      likesCount: 98,
      savesCount: 16,
      sharesCount: 22,
      createdAt: DateTime.parse('2026-08-20T10:24:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_25_26_preduprezhdayushchie_6',
      title: 'Предупреждающие знаки',
      description: '',
      videoUrl: 'assets/videos/26_preduprezhdayushchie_6.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Предупреждающие знаки',
      likesCount: 46,
      savesCount: 32,
      sharesCount: 27,
      createdAt: DateTime.parse('2026-08-20T11:24:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_26_27_bilet02_razresheno-li-vam-obognat',
      title: 'Билет 2, Вопрос 11',
      description: '',
      videoUrl: 'assets/videos/27_bilet02_razresheno-li-vam-obognat.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 11,
      likesCount: 20,
      savesCount: 19,
      sharesCount: 2,
      createdAt: DateTime.parse('2026-08-20T10:25:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_26_27_zapreshchayushchie_6',
      title: 'Запрещающие знаки',
      description: '',
      videoUrl: 'assets/videos/27_zapreshchayushchie_6.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Запрещающие знаки',
      likesCount: 55,
      savesCount: 36,
      sharesCount: 3,
      createdAt: DateTime.parse('2026-08-20T11:25:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_27_28_bilet02_mozhno-li-vam-vehat',
      title: 'Билет 2, Вопрос 2',
      description: '',
      videoUrl: 'assets/videos/28_bilet02_mozhno-li-vam-vehat.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 2,
      likesCount: 27,
      savesCount: 22,
      sharesCount: 7,
      createdAt: DateTime.parse('2026-08-20T10:26:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_27_28_osobyh-predpisaniy_5',
      title: 'Знаки особых предписаний',
      description: '',
      videoUrl: 'assets/videos/28_osobyh-predpisaniy_5.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Знаки особых предписаний',
      likesCount: 64,
      savesCount: 40,
      sharesCount: 9,
      createdAt: DateTime.parse('2026-08-20T11:26:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_28_29_bilet02_razreshaetsya-li-vam-ostanovitsya',
      title: 'Билет 2, Вопрос 3',
      description: '',
      videoUrl: 'assets/videos/29_bilet02_razreshaetsya-li-vam-ostanovitsya.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 2,
      targetQuestion: 3,
      likesCount: 34,
      savesCount: 25,
      sharesCount: 12,
      createdAt: DateTime.parse('2026-08-20T10:27:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_28_29_preduprezhdayushchie_7',
      title: 'Предупреждающие знаки',
      description: '',
      videoUrl: 'assets/videos/29_preduprezhdayushchie_7.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Предупреждающие знаки',
      likesCount: 73,
      savesCount: 9,
      sharesCount: 15,
      createdAt: DateTime.parse('2026-08-20T11:27:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd1_29_30_bilet03_vyezzhaya-s-gruntovoy-dorogi',
      title: 'Билет 3, Вопрос 1',
      description: '',
      videoUrl: 'assets/videos/30_bilet03_vyezzhaya-s-gruntovoy-dorogi.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'ticket',
      targetTicket: 3,
      targetQuestion: 1,
      likesCount: 41,
      savesCount: 28,
      sharesCount: 17,
      createdAt: DateTime.parse('2026-08-20T10:28:00Z'),
    ),
    ReelItem(
      id: 'reel_pdd2_29_30_zapreshchayushchie_7',
      title: 'Запрещающие знаки',
      description: '',
      videoUrl: 'assets/videos/30_zapreshchayushchie_7.mp4',
      author: 'ПДД 2026',
      country: 'ru',
      targetType: 'signs',
      targetSignCategory: 'Запрещающие знаки',
      likesCount: 82,
      savesCount: 13,
      sharesCount: 21,
      createdAt: DateTime.parse('2026-08-20T11:28:00Z'),
    ),
  ];

  /// Загрузка списка роликов (локальные ролики из assets/videos)
  Future<List<ReelItem>> fetchReels({String? countryCode}) async {
    final country = countryCode ?? CountryConfig.current.code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyCachePrefix$country');

    // Возвращаем встроенные ролики под текущую страну
    return _fallbackReels.where((r) {
      if (r.country == 'all') return true;
      return r.country == country;
    }).toList();
  }

  /// Проверка, лайкнут ли ролик локально
  Future<bool> isLiked(String reelId) async {
    final prefs = await SharedPreferences.getInstance();
    final likedList = prefs.getStringList(_keyLikedIds) ?? [];
    return likedList.contains(reelId);
  }

  /// Получение всех лайкнутых ID
  Future<Set<String>> getLikedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_keyLikedIds) ?? []).toSet();
  }

  /// Переключение лайка
  Future<bool> toggleLike(String reelId) async {
    final prefs = await SharedPreferences.getInstance();
    final likedList = prefs.getStringList(_keyLikedIds) ?? [];
    final isLikedNow = likedList.contains(reelId);

    if (isLikedNow) {
      likedList.remove(reelId);
      await prefs.setStringList(_keyLikedIds, likedList);
      return false;
    } else {
      likedList.add(reelId);
      await prefs.setStringList(_keyLikedIds, likedList);
      _sendLikeToServer(reelId);
      return true;
    }
  }

  /// Проверка, сохранен ли ролик
  Future<bool> isSaved(String reelId) async {
    final prefs = await SharedPreferences.getInstance();
    final savedList = prefs.getStringList(_keySavedIds) ?? [];
    return savedList.contains(reelId);
  }

  /// Получение всех сохраненных ID
  Future<Set<String>> getSavedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_keySavedIds) ?? []).toSet();
  }

  /// Переключение сохранения
  Future<bool> toggleSave(String reelId) async {
    final prefs = await SharedPreferences.getInstance();
    final savedList = prefs.getStringList(_keySavedIds) ?? [];
    final isSavedNow = savedList.contains(reelId);

    if (isSavedNow) {
      savedList.remove(reelId);
      await prefs.setStringList(_keySavedIds, savedList);
      return false;
    } else {
      savedList.add(reelId);
      await prefs.setStringList(_keySavedIds, savedList);
      return true;
    }
  }

  /// Получение количества шеров для ролика
  Future<int> getSharesCount(String reelId, int initialShares) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_keySharesPrefix$reelId') ?? initialShares;
  }

  /// Инкремент счетчика шеров
  Future<int> incrementShares(String reelId, int initialShares) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt('$_keySharesPrefix$reelId') ?? initialShares;
    final updated = current + 1;
    await prefs.setInt('$_keySharesPrefix$reelId', updated);
    return updated;
  }

  void _sendLikeToServer(String reelId) {
    if (!BackendConfig.hasNotifier) return;
    try {
      final uri = Uri.parse(
        '${BackendConfig.notifierUrl}/api/reels/$reelId/like',
      );
      http.post(uri).catchError((_) => http.Response('', 500));
    } catch (_) {}
  }

  /// Скачивание/получение закэшированного файла видео
  Future<File?> getCachedVideoFile(String videoUrl) async {
    if (kIsWeb) return null;
    try {
      final tempDir = await getTemporaryDirectory();
      final reelsDir = Directory('${tempDir.path}/reels_cache');
      if (!reelsDir.existsSync()) {
        await reelsDir.create(recursive: true);
      }
      final filename =
          'reel_${videoUrl.hashCode.abs()}_${videoUrl.split('?').first.split('/').last}';
      final file = File('${reelsDir.path}/$filename');
      if (await file.exists() && await file.length() > 0) {
        return file;
      }
      // Скачиваем
      final response = await http.get(Uri.parse(videoUrl));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
    } catch (e) {
      debugPrint('Error caching reel video: $e');
    }
    return null;
  }

  /// Поделиться видеороликом (.mp4 файл + текст со ссылкой на приложение)
  Future<void> shareReel(ReelItem reel) async {
    final country = CountryConfig.current;
    final appLink = country.code == 'rs'
        ? 'https://rs.pdd-drive.online/'
        : 'https://pdd-drive.ru/links/?ref=share_reel';

    final text = '🚗 ${reel.title}\n\n'
        '📱 Больше разборов и билеты в приложении: $appLink';

    if (!kIsWeb) {
      final cachedFile = await getCachedVideoFile(reel.videoUrl);
      if (cachedFile != null && await cachedFile.exists()) {
        await SharePlus.instance.share(
          ShareParams(
            text: text,
            subject: reel.title,
            files: [XFile(cachedFile.path, mimeType: 'video/mp4')],
          ),
        );
        return;
      }
    }

    await SharePlus.instance.share(
      ShareParams(
        text: '$text\n▶️ Видео: ${reel.videoUrl}',
        subject: reel.title,
      ),
    );
  }
}
