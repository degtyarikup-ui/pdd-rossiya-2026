import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/acquisition_service.dart';

void main() {
  test('Play referrer preserves source and campaign without mixing store', () {
    final fields = AcquisitionService.parseReferrer(
      'utm_source=threads&utm_campaign=launch_48&utm_medium=social',
      'play_referrer',
    );
    expect(fields['marketingSource'], 'threads');
    expect(fields['marketingCampaign'], 'launch_48');
    expect(fields['attributionMethod'], 'play_referrer');
    expect(fields.containsKey('source'), isFalse);
  });
  test('organic and invalid sources never turn into a Threads attribution', () {
    expect(
      AcquisitionService.parseReferrer(
        'utm_source=google-play',
        'play_referrer',
      ),
      isEmpty,
    );
    expect(
      AcquisitionService.parseReferrer('utm_source=__proto__', 'play_referrer'),
      isEmpty,
    );
    expect(
      AcquisitionService.parseReferrer(
        'utm_source=th&utm_campaign=%3Cscript%3E',
        'play_referrer',
      ),
      {'marketingSource': 'threads', 'attributionMethod': 'play_referrer'},
    );
  });
}
