// This SDK's own defaults for the customisable texts on the opening screens:
// consent, contact codes, document selection and the ready primers. Each is
// the wording this screen showed before the texts became customisable, so a
// workflow that sets nothing sees no change. The KEY is the shared contract;
// the wording may differ from the web SDK's.

const Map<String, String> kWelcomeTextDefaults = {
  'welcome.title': 'Identity Verification',
  'welcome.description':
      'We need to verify your identity to comply with regulatory requirements. This process is quick and secure.',
  'welcome.process.heading': 'During this process we will',
  'welcome.process.verifyId': 'Verify your government-issued ID',
  'welcome.process.personalInfo': 'Collect basic personal information',
  'welcome.process.businessDetails': 'Collect your business registration details',
  'welcome.process.businessRegistry': 'Verify your business against the official registry',
  'welcome.process.addressPin': 'Pin your home address on a map',
  'welcome.process.addressDetails': 'Confirm the details only you can know',
  'welcome.process.faceSelfie': 'Take a quick selfie with liveness checks',
  'welcome.process.faceMatch': 'We match it against your enrolled face',
  'welcome.process.faceEnrol': 'It becomes your face check for next time',
  'welcome.process.contactScope': 'Confirm your contact details with a one-time code',
  'welcome.process.contactEmailAndPhone': 'Confirm your email and phone number with a one-time code',
  'welcome.process.contactEmail': 'Confirm your email with a one-time code',
  'welcome.process.contactPhone': 'Confirm your phone number with a one-time code',
  'welcome.process.captureDocument': 'Capture a photo of your ID document',
  'welcome.process.selfie': 'Take a selfie for facial verification',
  'welcome.process.supportingDocuments': 'Upload supporting documents',
  'welcome.process.proofOfAddress': 'Upload a proof of address document',
  'welcome.process.addressMap': 'Pin your address on a map',
  'welcome.process.questions': 'Answer a few short questions',
  'welcome.process.keyPeople': "List the company's directors and owners",
  'welcome.process.businessDocuments': 'Upload supporting business documents',
  'welcome.process.applicant': 'Verify your own identity',
  'welcome.secureNote': 'Your data is encrypted and securely processed',
  'contact.email.title': 'Verify your email',
  'contact.email.intro': "We'll send a one-time code to confirm this email belongs to you.",
  'contact.phone.title': 'Verify your phone number',
  'contact.email.label': 'Email address',
  'contact.phone.label': 'Phone number',
  'contact.channel.question': 'How should we send it?',
  'contact.sendCode': 'Send code',
  'contact.skip': 'Skip for now',
  'contact.email.footer': 'We only use this to verify your identity.',
  'contact.phone.footer': 'Standard message rates may apply.',
  'contact.code.resend': 'Resend code',
  'contact.verifyCode': 'Verify code',
  'selectDocument.country.title': 'Where was your ID issued?',
  'selectDocument.country.description': 'Choose the country that issued your identity document.',
  'selectDocument.idType.title': 'Select ID Type',
  'selectDocument.idType.description': "Choose the type of identification document you'd like to use.",
  'selectDocument.idInput.description': 'We’ll check this against the official record.',
  'primer.document.title': "You're about to scan your ID",
  'primer.document.body':
      "We'll photograph your document and read it automatically. Nothing is shared until you submit.",
  'primer.document.checklist1': 'Have your physical document with you',
  'primer.document.checklist2': 'Find even lighting, avoid glare',
  'primer.document.checklist3': 'Takes about a minute',
  'primer.selfie.title': "Let's confirm you're really here",
  'primer.selfie.body':
      "You'll follow a few short prompts on screen. This proves a real person is present, not a photo or a recording.",
  'primer.selfie.bodyPassive':
      "You'll hold still and look at the camera for a moment. This proves a real person is present, not a photo or a recording.",
  'primer.selfie.checklist1': 'Put your face in the circle',
  'primer.selfie.checklist2': 'Take off glasses or anything covering your face',
  'primer.selfie.checklist4':
      'Choose a bright spot, with the light in front of you',
  'primer.selfie.checklist5':
      'Keep glare and shiny reflections off your face',
  'primer.readyButton': "I'm ready",
  'primer.camera.title': 'Allow camera access',
  'primer.camera.body': 'When prompted, allow camera access to continue your verification.',
  'primer.camera.bodyDocument': 'When prompted, allow camera access to photograph your document.',
  'primer.camera.button': 'Grant access',
};
