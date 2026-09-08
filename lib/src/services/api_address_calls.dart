part of 'api_service.dart';

// ─── Address Intelligence calls ──────────────────────────────────────────────
//
// Split from api_address.dart (200-line rule). An extension on the service so
// the address surface reads as one unit, and a `part` so it can reach the
// library-private Dio client and error mapper.
//
// Two search backends sit behind one flow: Places autocomplete (as-you-type)
// and the basic explicit-submit search. Which one applies is decided by
// `serverConfig.addressSearchMode`, never by trying one and falling back.

extension KYCApiAddress on KYCApiService {
  /// Forward address search for the basic backend.
  ///
  /// EXPLICIT SUBMIT ONLY. Never call this per keystroke: the server's map
  /// source forbids autocomplete, and the request budget has to be spent on
  /// the query the applicant actually meant rather than on every prefix of it.
  /// 404s when the platform has no geocoder configured.
  Future<List<AddressSearchHit>> addressSearch(
    String query, {
    String? country,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/kyc/address/search',
        queryParameters: {
          'q': query,
          if (country != null && country.isNotEmpty) 'country': country,
        },
      );
      final raw = response.data?['results'];
      if (raw is! List) return const [];
      return [
        for (final row in raw.whereType<Map>())
          if (AddressSearchHit.fromJson(row.cast<String, dynamic>())
              case final AddressSearchHit hit)
            hit,
      ];
    } on DioException catch (e) {
      throw _mapDioError(e, fallbackError: 'search_unavailable');
    }
  }

  /// Auth headers for an image the review card loads directly.
  Map<String, String> get imageHeaders => {
        'Authorization': 'Bearer $apiKey',
        'X-SDK-Version': kSdkVersion,
      };

  /// The pinned location as a PICTURE, for the review card.
  ///
  /// A confirmation screen wants a photograph of the place, not a second
  /// instrument: a live map there invites a drag that goes nowhere and carries
  /// the vendor's own controls over the SDK's chrome. The key lives on the
  /// server, so the URL is ours and Image.network carries the header.
  String staticMapUrl({
    required double lat,
    required double lng,
    int zoom = 16,
    int width = 640,
    int height = 360,
  }) =>
      '$baseUrl/api/kyc/address/static-map'
      '?lat=$lat&lng=$lng&zoom=$zoom&width=$width&height=$height';

  /// The framed Street View entrance, as bytes the review card can show.
  ///
  /// The browser key never reaches this SDK (the framed page holds it), so the
  /// thumbnail comes through the server, which does. Best-effort: a failure
  /// leaves the review without the thumbnail, never without the step. Mirrors
  /// the web and RN SDKs' addressStreetViewPreview.
  Future<Uint8List?> addressStreetViewPreview({
    required String panoId,
    required double heading,
    required double pitch,
    required double fov,
  }) async {
    try {
      final response = await _dio.get<List<int>>(
        '/api/kyc/address/street-view-preview',
        queryParameters: {
          'panoId': panoId,
          'heading': heading,
          'pitch': pitch,
          'fov': fov,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  /// The street line for a pin, for the summary card after a locate or a drag.
  ///
  /// Display only: it is never fed into corroboration, and the applicant's own
  /// confirmed label is what the submission carries.
  Future<AddressReverseResult> addressReverse(double lat, double lng) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/kyc/address/reverse',
        queryParameters: {'lat': lat, 'lng': lng},
      );
      return AddressReverseResult.fromJson(response.data ?? const {});
    } on DioException catch (e) {
      throw _mapDioError(e, fallbackError: 'search_unavailable');
    }
  }

  /// Places-backed as-you-type suggestions.
  ///
  /// [session] is ONE token per typing session, reused for every keystroke and
  /// minted afresh after a details call: it is the billing unit, so Google
  /// bills per typing session rather than per keystroke. Debounce client-side
  /// and do not call below three trimmed characters.
  ///
  /// [near] is the device fix, a RANKING bias so nearby streets come first:
  /// without it "Awolowo Road" in Calabar ranks against every Awolowo Road in
  /// the country. Mirrors the web and RN SDKs' addressAutocomplete.
  Future<List<PlaceSuggestion>> addressAutocomplete(
    String query, {
    required String session,
    String? country,
    MapLatLng? near,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/kyc/address/autocomplete',
        queryParameters: {
          'q': query,
          'session': session,
          if (country != null && country.isNotEmpty) 'country': country,
          if (near != null) ...{'lat': '${near.lat}', 'lng': '${near.lng}'},
        },
      );
      final raw = response.data?['suggestions'];
      if (raw is! List) return const [];
      return [
        for (final row in raw.whereType<Map>())
          if (PlaceSuggestion.fromJson(row.cast<String, dynamic>())
              case final PlaceSuggestion suggestion)
            suggestion,
      ];
    } on DioException catch (e) {
      throw _mapDioError(e, fallbackError: 'search_unavailable');
    }
  }

  /// Resolve a picked suggestion to coordinates plus its structured pieces.
  /// This call CLOSES the autocomplete billing session, so the caller mints a
  /// fresh [session] token before the next keystroke.
  Future<ResolvedPlace> addressPlace(
    String placeId, {
    required String session,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/kyc/address/place/${Uri.encodeComponent(placeId)}',
        queryParameters: {'session': session},
      );
      final place = response.data?['place'];
      if (place is! Map) {
        throw const KYCApiException(
          statusCode: 404,
          error: 'place_not_found',
          message:
              'That address could not be resolved. Place the pin by hand instead.',
        );
      }
      return ResolvedPlace.fromJson(place.cast<String, dynamic>());
    } on DioException catch (e) {
      throw _mapDioError(e, fallbackError: 'place_not_found');
    }
  }
}
