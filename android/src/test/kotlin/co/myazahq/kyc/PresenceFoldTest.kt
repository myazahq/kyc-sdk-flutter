package co.myazahq.kyc

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Pins PresenceFold to the canonical cross-language vectors in
 * test/presence_fold_vectors.json (package root). The RN SDK's
 * foldVectors.test.ts and the iOS PresenceFoldTests.swift pin the other two
 * implementations against the same file — change the fold rule in one
 * language and the vectors, and the other two, in the same commit.
 */
class PresenceFoldTest {
  private fun vectorsFile(): File {
    // Gradle runs unit tests with the module directory (android/) as the
    // working directory; walk up until the package-root test file appears so
    // an IDE runner with a different cwd still finds it.
    var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
    repeat(6) {
      val candidate = File(dir, "test/presence_fold_vectors.json")
      if (candidate.isFile) return candidate
      dir = dir?.parentFile ?: return@repeat
    }
    throw AssertionError("presence_fold_vectors.json not found above ${System.getProperty("user.dir")}")
  }

  @Test
  fun matchesCanonicalVectors() {
    val doc = JSONObject(vectorsFile().readText())
    val vectors = doc.getJSONArray("vectors")
    assertTrue("meaningful case set", vectors.length() >= 10)
    for (i in 0 until vectors.length()) {
      val v = vectors.getJSONObject(i)
      val name = v.getString("name")
      val folded = PresenceFold.foldSpanIntoDays(
        v.getLong("enterMs"),
        v.getLong("exitMs"),
        v.getInt("offsetMinutes"),
      )
      val expected = v.getJSONArray("expected")
      assertEquals("$name: day count", expected.length(), folded.size)
      for (j in 0 until expected.length()) {
        val e = expected.getJSONObject(j)
        assertEquals("$name[$j].day", e.getString("day"), folded[j].day)
        assertEquals("$name[$j].dwellMinutes", e.getInt("dwellMinutes"), folded[j].dwellMinutes)
        assertEquals("$name[$j].nightPresent", e.getBoolean("nightPresent"), folded[j].nightPresent)
      }
    }
  }

  @Test
  fun matchesCanonicalCheckInVectors() {
    val doc = JSONObject(vectorsFile().readText())
    assertEquals("check-in interval", doc.getLong("checkpointMs"), PresenceFold.CHECKPOINT_MS)
    assertEquals("first check-in", doc.getLong("firstCheckpointMs"), PresenceFold.FIRST_CHECKPOINT_MS)
    val vectors = doc.getJSONArray("checkpoints")
    assertTrue("meaningful case set", vectors.length() >= 6)
    for (i in 0 until vectors.length()) {
      val v = vectors.getJSONObject(i)
      val name = v.getString("name")
      val enterAt = if (v.isNull("enterAt")) null else v.getLong("enterAt")
      val stayStart = if (v.isNull("stayStart")) null else v.getLong("stayStart")
      val out = PresenceFold.checkpointStay(enterAt, v.getLong("atMs"), v.getInt("offsetMinutes"), stayStart)
      val expected = v.getJSONObject("expected")
      assertEquals("$name: enterAt", expected.getLong("enterAt"), out.enterAt)
      assertEquals("$name: stayStart", expected.getLong("stayStart"), out.stayStart)
      val days = expected.getJSONArray("days")
      assertEquals("$name: day count", days.length(), out.days.size)
      for (j in 0 until days.length()) {
        val e = days.getJSONObject(j)
        assertEquals("$name[$j].day", e.getString("day"), out.days[j].day)
        assertEquals("$name[$j].dwellMinutes", e.getInt("dwellMinutes"), out.days[j].dwellMinutes)
        assertEquals("$name[$j].nightPresent", e.getBoolean("nightPresent"), out.days[j].nightPresent)
      }
    }
  }
}
