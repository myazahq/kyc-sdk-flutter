// This SDK's own defaults for the customisable texts on the closing screens
// (submitting, success, the face-check verdicts) and the shared buttons. Each
// is the wording the screen showed before the texts became customisable.

const Map<String, String> kResultTextDefaults = {
  'result.submitting.title': 'Submitting your verification',
  'result.submitting.description': 'Please wait a moment.',
  'result.success.title': 'Verification Submitted!',
  'result.success.description.individual':
      "Your identity verification has been submitted for review. You'll be notified of the result.",
  'result.success.description.business':
      "Your business verification has been submitted for review. You'll be notified of the result.",
  'result.faceCheck.checking.title': "Checking it's you",
  'result.faceCheck.checking.description':
      'Matching your selfie against the photo on record. This usually takes a few seconds.',
  'result.faceCheck.sending.title': 'Sending your face check',
  'result.faceCheck.sending.description': 'This only takes a moment.',
  'result.faceEnrolment.saving.title': 'Saving your selfie',
  'result.faceEnrolment.saving.description': 'It becomes the reference for your future face checks.',
  'result.faceCheck.verified.title': "You're verified",
  'result.faceCheck.verified.description': 'Your face matched the photo on record.',
  'result.faceCheck.declined.title': "We couldn't confirm it's you",
  'result.faceCheck.declined.description': "Your face didn't match the photo on record.",
  'result.faceCheck.inReview.title': 'Under review',
  'result.faceCheck.inReview.description': "A reviewer will take a look. You'll be notified of the outcome.",
  'result.faceCheck.submitted.title': 'Check submitted',
  'result.faceCheck.submitted.description': "You'll be notified of the result.",
  'result.faceCheck.timeout.title': 'Still checking',
  'result.faceCheck.timeout.description':
      "This is taking longer than usual. You'll be notified as soon as it's done.",
  'common.continue': 'Continue',
  'common.continueAnyway': 'Continue anyway',
  'common.done': 'Done',
  'common.retake': 'Retake',
  'common.skip': 'Skip',
};
