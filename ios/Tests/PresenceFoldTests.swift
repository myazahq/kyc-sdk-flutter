import XCTest
@testable import myaza_kyc_sdk_flutter

/// Pins PresenceFold to the canonical cross-language vectors in
/// test/presence_fold_vectors.json (package root). The RN SDK's
/// foldVectors.test.ts and Android's PresenceFoldTest.kt pin the other two
/// implementations against the same file — change the fold rule in one
/// language and the vectors, and the other two, in the same commit.
final class PresenceFoldTests: XCTestCase {
  private func vectorsURL() -> URL {
    // ios/Tests/PresenceFoldTests.swift → ../../test/presence_fold_vectors.json
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("test/presence_fold_vectors.json")
  }

  func testMatchesCanonicalVectors() throws {
    let data = try Data(contentsOf: vectorsURL())
    let doc = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let vectors = doc["vectors"] as! [[String: Any]]
    XCTAssertGreaterThanOrEqual(vectors.count, 10, "meaningful case set")
    for v in vectors {
      let name = v["name"] as! String
      let folded = PresenceFold.foldSpanIntoDays(
        enterMs: (v["enterMs"] as! NSNumber).int64Value,
        exitMs: (v["exitMs"] as! NSNumber).int64Value,
        offsetMinutes: (v["offsetMinutes"] as! NSNumber).intValue
      )
      let expected = v["expected"] as! [[String: Any]]
      XCTAssertEqual(folded.count, expected.count, "\(name): day count")
      for (i, e) in expected.enumerated() where i < folded.count {
        XCTAssertEqual(folded[i].day, e["day"] as! String, "\(name)[\(i)].day")
        XCTAssertEqual(
          folded[i].dwellMinutes, (e["dwellMinutes"] as! NSNumber).intValue,
          "\(name)[\(i)].dwellMinutes"
        )
        XCTAssertEqual(
          folded[i].nightPresent, (e["nightPresent"] as! NSNumber).boolValue,
          "\(name)[\(i)].nightPresent"
        )
      }
    }
  }

  func testMatchesCanonicalCheckInVectors() throws {
    let data = try Data(contentsOf: vectorsURL())
    let doc = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual((doc["checkpointMs"] as! NSNumber).int64Value, PresenceFold.checkpointMs, "check-in interval")
    XCTAssertEqual((doc["firstCheckpointMs"] as! NSNumber).int64Value, PresenceFold.firstCheckpointMs, "first check-in")
    let vectors = doc["checkpoints"] as! [[String: Any]]
    XCTAssertGreaterThanOrEqual(vectors.count, 6, "meaningful case set")
    for v in vectors {
      let name = v["name"] as! String
      let enterAt = (v["enterAt"] as? NSNumber)?.int64Value
      let out = PresenceFold.checkpointStay(
        enterAt: enterAt,
        atMs: (v["atMs"] as! NSNumber).int64Value,
        offsetMinutes: (v["offsetMinutes"] as! NSNumber).intValue,
        stayStart: (v["stayStart"] as? NSNumber)?.int64Value
      )
      let expected = v["expected"] as! [String: Any]
      XCTAssertEqual(out.enterAt, (expected["enterAt"] as! NSNumber).int64Value, "\(name): enterAt")
      XCTAssertEqual(out.stayStart, (expected["stayStart"] as! NSNumber).int64Value, "\(name): stayStart")
      let days = expected["days"] as! [[String: Any]]
      XCTAssertEqual(out.days.count, days.count, "\(name): day count")
      for (i, e) in days.enumerated() where i < out.days.count {
        XCTAssertEqual(out.days[i].day, e["day"] as! String, "\(name)[\(i)].day")
        XCTAssertEqual(out.days[i].dwellMinutes, (e["dwellMinutes"] as! NSNumber).intValue, "\(name)[\(i)].dwellMinutes")
        XCTAssertEqual(out.days[i].nightPresent, (e["nightPresent"] as! NSNumber).boolValue, "\(name)[\(i)].nightPresent")
      }
    }
  }
}

