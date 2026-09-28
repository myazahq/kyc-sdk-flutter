// This SDK's own defaults for the customisable texts on the form screens:
// proof of address, supporting documents, the business application, key
// people and the questionnaire. Each is the wording the screen showed before
// the texts became customisable (an em dash rewritten as a comma).

const Map<String, String> kFormTextDefaults = {
  'proofOfAddress.title': 'Proof of address',
  'proofOfAddress.documentType': 'Document type',
  'proofOfAddress.kind.utilityBill': 'Utility bill',
  'proofOfAddress.kind.bankStatement': 'Bank statement',
  'proofOfAddress.kind.tenancyAgreement': 'Tenancy agreement',
  'proofOfAddress.kind.governmentDocument': 'Government-issued document',
  'proofOfAddress.kind.other': 'Other document',
  'proofOfAddress.uploaded': 'Document uploaded',
  'supportingDocuments.title': 'Supporting documents',
  'supportingDocuments.intro.optional.one':
      'Upload this document if you have it, so we can keep it on file. You can skip it.',
  'supportingDocuments.intro.optional.many':
      'Upload any of these you have, so we can keep them on file. You can skip the rest.',
  'supportingDocuments.intro.required.one': 'We need this document to continue. Upload it below.',
  'supportingDocuments.card.required': 'Required',
  'supportingDocuments.card.optional': 'Optional',
  'supportingDocuments.card.reads': 'What we read from it',
  'business.details.title': 'Business Details',
  'business.details.description':
      'Provide your business registration details for verification against the official registry.',
  'business.details.countryLabel': 'Country of registration',
  'business.search.manualEntry': 'Enter the details myself',
  'business.details.registrationNumberLabel': 'Registration number',
  'business.details.nameLabel': 'Registered business name',
  'business.companyInfo.title': 'Company information',
  'business.companyInfo.description': 'We verify these details against the official registry record.',
  'business.contactEmail.label': 'Contact email for owner verification',
  'business.contactEmail.hint':
      "We'll email this address a link for your directors and owners to verify their identity.",
  'business.details.checkNote':
      'Continue checks this business against the official register and brings back its details.',
  'business.details.confirm': 'Confirm details & continue',
  'business.documents.title': 'Business documents',
  'business.documents.description':
      'Upload the supporting documents for your business. Each one must clearly show the registered business name and registration number. Required documents are marked with *.',
  'business.applicant.title': 'Now verify your own identity',
  'business.applicant.description':
      'Tell us your role at the business, then verify your identity with a government-issued ID.',
  'business.applicant.notice':
      'Regulations require the person submitting a business application to verify their own identity. This only takes a minute.',
  'business.applicant.whoLabel': 'Are you one of the people you listed?',
  'business.applicant.notListed': "I'm not one of these people",
  'business.applicant.selfNote':
      "You'll verify your identity at the end of this form, so no separate invite link is needed for you.",
  'business.applicant.roleLabel': 'Your role at the business',
  'keyPeople.title': 'Directors & Owners',
  'keyPeople.description':
      "List the company's directors and owners. Each person will receive a link to verify their identity; a shareholder that is itself a company is recorded rather than asked to verify.",
  'keyPeople.hints.skippable':
      "You can skip this if you're unsure. We'll identify directors and owners from the official registry. Adding them here speeds up the review.",
  'keyPeople.section.ubos.add': 'Add a beneficial owner',
  'keyPeople.section.shareholders.add': 'Add a shareholder',
  'keyPeople.section.representatives.description': 'People who act on behalf of the company.',
  'keyPeople.section.representatives.add': 'Add a representative',
  'keyPeople.pending.title': 'Working out who else needs to verify',
  'keyPeople.pending.body': "We are checking the official register for the company's directors and owners.",
  'keyPeople.await.allDone': 'Everyone on this application has completed their identity check.',
  'keyPeople.await.intro':
      'To complete the review, the people below must verify their identity with a KYC check. Anyone with an email on file has already been sent their link.',
  'keyPeople.await.linkValidity': 'Links are valid for 14 days.',
  'questionnaire.title': 'A Few More Questions',
  'questionnaire.description': 'Please answer the following to complete your verification.',
  'questionnaire.detailLabel': 'Please specify',
  'questionnaire.yes': 'Yes',
  'questionnaire.no': 'No',
};
