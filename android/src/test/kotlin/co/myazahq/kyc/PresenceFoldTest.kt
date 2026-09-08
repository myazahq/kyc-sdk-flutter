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
}
