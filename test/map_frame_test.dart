import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/map_frame.dart';
import 'package:myaza_kyc_sdk_flutter/src/utils/map_tiles.dart';

// The framed map's protocol, mirrored from the web and RN SDKs: no origin on
// an app URL (the page proves it has no embedder instead), validate-and-drop
// on everything the channel delivers, and a recentre that reaches the page as
// a script.

void main() {
  group('the framed street-view page', streetViewTests);
  test(
      'buildMapFrameSrc keeps the grant and mode, adds the view, never an origin',
      () {
    final src = Uri.parse(buildMapFrameSrc(
      'https://trust.myaza.co/embed/map?grant=abc&mode=app',
      center: const MapLatLng(6.4, 3.4),
      zoom: 12,
      hasPin: true,
      theme: 'dark',
      primaryColor: '#5645F5',
    ));
    expect(src.queryParameters['grant'], 'abc');
    expect(src.queryParameters['mode'], 'app');
    expect(src.queryParameters['zoom'], '16');
    expect(src.queryParameters['theme'], 'dark');
    expect(src.queryParameters.containsKey('origin'), isFalse);
  });

  test('parseMapFrameMessage accepts the channel JSON, drops the rest', () {
    expect(parseMapFrameMessage('{"source":"myaza-map","type":"ready"}'),
        isA<MapFrameReady>());
    final pin = parseMapFrameMessage(
        '{"source":"myaza-map","type":"pin","lat":1,"lng":2}');
    expect(pin, isA<MapFramePin>());
    expect((pin as MapFramePin).pin.lat, 1);
    expect(
        parseMapFrameMessage(
            '{"source":"myaza-map","type":"pin","lat":91,"lng":0}'),
        isNull);
    expect(parseMapFrameMessage('{"source":"other","type":"ready"}'), isNull);
    expect(parseMapFrameMessage('not json'), isNull);
  });

  test('centerCommandScript calls the page global with a JSON string', () {
    final script = centerCommandScript(const MapLatLng(6.4, 3.4));
    expect(script, contains('window.__myazaMapCommand('));
    expect(script, contains('myaza-sdk'));
    expect(script.trim().endsWith('true;'), isTrue);
  });

  test('samePin tolerates float noise only', () {
    expect(
        samePin(const MapLatLng(1, 2), const MapLatLng(1 + 1e-9, 2)), isTrue);
    expect(samePin(const MapLatLng(1, 2), const MapLatLng(1.001, 2)), isFalse);
    expect(samePin(null, const MapLatLng(1, 2)), isFalse);
  });
}

// ─── The framed street-view page ─────────────────────────────────────────────
void streetViewTests() {
  const mapUrl = 'https://trust.myaza.co/embed/map?grant=abc&mode=app';

  test('streetViewFrameUrlOf swaps the path, keeping the grant and app mode',
      () {
    expect(streetViewFrameUrlOf(mapUrl),
        'https://trust.myaza.co/embed/street-view?grant=abc&mode=app');
    expect(streetViewFrameUrlOf('https://trust.myaza.co/embed/other?grant=abc'),
        isNull);
    expect(streetViewFrameUrlOf('::not a url::'), isNull);
  });

  test('buildStreetViewFrameSrc adds the pin and theme, never an origin', () {
    final src = Uri.parse(buildStreetViewFrameSrc(
      streetViewFrameUrlOf(mapUrl)!,
      pin: const MapLatLng(6.4, 3.4),
      theme: 'dark',
    ));
    expect(src.path, '/embed/street-view');
    expect(src.queryParameters['grant'], 'abc');
    expect(src.queryParameters['mode'], 'app');
    expect(src.queryParameters['lat'], '6.4');
    expect(src.queryParameters['theme'], 'dark');
    expect(src.queryParameters.containsKey('origin'), isFalse);
  });

  test('parseStreetViewFrameMessage accepts the page messages, drops the rest',
      () {
    expect(parseStreetViewFrameMessage('{"source":"myaza-map","type":"sv-ready"}'),
        isA<StreetViewReady>());
    expect(
        parseStreetViewFrameMessage(
            '{"source":"myaza-map","type":"sv-unavailable"}'),
        isA<StreetViewUnavailable>());
    final pov = parseStreetViewFrameMessage(
        '{"source":"myaza-map","type":"sv-pov","panoId":"p","heading":90,"pitch":0,"viewFov":75}');
    expect(pov, isA<StreetViewPov>());
    expect((pov! as StreetViewPov).viewFov, 75);
    expect(
        parseStreetViewFrameMessage(
            '{"source":"myaza-map","type":"sv-pov","panoId":"","heading":90,"pitch":0,"viewFov":75}'),
        isNull);
    expect(
        parseStreetViewFrameMessage(
            '{"source":"other","type":"sv-ready"}'),
        isNull);
    expect(parseStreetViewFrameMessage('{not json'), isNull);
  });
}
