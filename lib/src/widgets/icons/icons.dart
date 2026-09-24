import 'package:hugeicons/hugeicons.dart';

import 'app_icon.dart';
import 'glyphs.dart';

export 'app_icon.dart';

/// Every icon the SDK draws, under the name the call site already used.
///
/// The names are Lucide's, which this SDK drew before the set changed. Keeping
/// them is what lets the web, React Native and Flutter SDKs stay in lockstep by
/// NAME rather than by glyph: `MyazaIcons.fingerprint` means the same thing in
/// all three, whatever each one renders it with.
///
/// Wherever the web SDK already carries an icon, the entry here resolves to the
/// SAME Hugeicons glyph, taken from its mapping through the set's own alias
/// table rather than guessed from the name. The rest were chosen by meaning
/// against the catalogue.
///
/// Adding one: add the constant, and add it to the web SDK's barrel under the
/// same name if that SDK draws it too. Nothing outside this directory may
/// import `package:hugeicons` directly - see icons_test.dart.
class MyazaIcons {
  MyazaIcons._();

  static const MyazaIconData arrowLeft = HugeIcons.strokeRoundedArrowLeft01;
  static const MyazaIconData arrowRight = HugeIcons.strokeRoundedArrowRight01;
  static const MyazaIconData badgeCheck = HugeIcons.strokeRoundedBadgeCheck;
  static const MyazaIconData bellRing = HugeIcons.strokeRoundedBellRing;
  static const MyazaIconData bookUser = HugeIcons.strokeRoundedBookUser;
  static const MyazaIconData building2 = HugeIcons.strokeRoundedBuilding02;
  static const MyazaIconData calendar = HugeIcons.strokeRoundedCalendar01;
  static const MyazaIconData camera = HugeIcons.strokeRoundedCamera01;
  static const MyazaIconData cameraOff = HugeIcons.strokeRoundedCameraOff01;
  static const MyazaIconData check = HugeIcons.strokeRoundedCheck;
  static const MyazaIconData chevronDown = HugeIcons.strokeRoundedChevronDown;
  static const MyazaIconData chevronRight = HugeIcons.strokeRoundedChevronRight;
  static const MyazaIconData circle = HugeIcons.strokeRoundedCircle;
  static const MyazaIconData circleAlert = HugeIcons.strokeRoundedAlertCircle;
  static const MyazaIconData circleCheck =
      HugeIcons.strokeRoundedCheckmarkCircle02;
  static const MyazaIconData circleDashed = HugeIcons.strokeRoundedCircleDashed;
  static const MyazaIconData circleHelp = HugeIcons.strokeRoundedHelpCircle;
  static const MyazaIconData circleX = HugeIcons.strokeRoundedCancelCircle;
  static const MyazaIconData contact = HugeIcons.strokeRoundedContact;
  static const MyazaIconData copy = HugeIcons.strokeRoundedCopy;
  static const MyazaIconData creditCard = HugeIcons.strokeRoundedCreditCard;
  static const MyazaIconData eye = HugeIcons.strokeRoundedEye;
  static const MyazaIconData eyeOff = HugeIcons.strokeRoundedEyeOff;
  static const MyazaIconData fileText = HugeIcons.strokeRoundedFile02;
  static const MyazaIconData filter = HugeIcons.strokeRoundedFilter;
  static const MyazaIconData fingerprint = HugeIcons.strokeRoundedFingerPrint;
  static const MyazaIconData flaskConical = HugeIcons.strokeRoundedFlaskConical;
  static const MyazaIconData globe = HugeIcons.strokeRoundedGlobe;
  static const MyazaIconData house = HugeIcons.strokeRoundedHome01;
  static const MyazaIconData idCard = HugeIcons.strokeRoundedIdentityCard;
  static const MyazaIconData image = HugeIcons.strokeRoundedImage01;
  static const MyazaIconData imageUp = HugeIcons.strokeRoundedImageUpload;
  static const MyazaIconData info = HugeIcons.strokeRoundedInformationCircle;
  static const MyazaIconData landmark = HugeIcons.strokeRoundedLandmark;
  static const MyazaIconData lightbulb = HugeIcons.strokeRoundedBulb;
  static const MyazaIconData locateFixed = HugeIcons.strokeRoundedGps02;
  static const MyazaIconData lock = HugeIcons.strokeRoundedLock;
  static const MyazaIconData mail = HugeIcons.strokeRoundedMail01;
  static const MyazaIconData mapPin = HugeIcons.strokeRoundedMapPin;
  static const MyazaIconData mapPinCheck =
      HugeIcons.strokeRoundedLocationCheck01;
  static const MyazaIconData mapPinHouse = HugeIcons.strokeRoundedMapPinHouse;
  static const MyazaIconData mapPinned = HugeIcons.strokeRoundedLocation02;
  // Hugeicons' Maximize02 is a PINCH GESTURE glyph (a hand), not the corner
  // arrows Lucide's `maximize2` describes. `strokeRoundedExpand` is the same
  // drawing the web SDK and the dashboard use for this.
  static const MyazaIconData maximize2 = HugeIcons.strokeRoundedExpand;
  static const MyazaIconData messageSquare = HugeIcons.strokeRoundedMessage01;
  static const MyazaIconData minus = HugeIcons.strokeRoundedMinusSign;
  static const MyazaIconData moon = HugeIcons.strokeRoundedMoon;
  // Lucide's `moveLeft` is a LONG arrow: a full-width shaft with a small head.
  // Hugeicons has no equivalent — its MoveLeft is a MOVE affordance (an arrow
  // trailing a dot), ArrowLeft/ArrowLeft01 are bare chevrons with no shaft,
  // ArrowLeft03/05 run into a vertical bar, and the longest true arrow,
  // ArrowLeft02, spans only 13.5 of 24 units against Lucide's 20. So this one
  // glyph is drawn locally, exactly as the web SDK draws it.
  static const MyazaIconData moveLeft = kLongArrowLeft;
  static const MyazaIconData nfc = HugeIcons.strokeRoundedNfc;
  static const MyazaIconData pencil = HugeIcons.strokeRoundedPencil;
  static const MyazaIconData pencilLine = HugeIcons.strokeRoundedPencilEdit01;
  static const MyazaIconData plus = HugeIcons.strokeRoundedAdd01;
  static const MyazaIconData radar = HugeIcons.strokeRoundedRadar01;
  static const MyazaIconData receiptText = HugeIcons.strokeRoundedReceiptText;
  static const MyazaIconData refreshCcw = HugeIcons.strokeRoundedRefresh;
  static const MyazaIconData refreshCw = HugeIcons.strokeRoundedRefreshCw;
  static const MyazaIconData rotateCcw = HugeIcons.strokeRoundedRotateLeft01;
  static const MyazaIconData scan = HugeIcons.strokeRoundedScan;
  static const MyazaIconData scanFace = HugeIcons.strokeRoundedFaceId;
  static const MyazaIconData scanLine = HugeIcons.strokeRoundedScan;
  static const MyazaIconData search = HugeIcons.strokeRoundedSearch01;
  static const MyazaIconData share2 = HugeIcons.strokeRoundedShare01;
  static const MyazaIconData shieldCheck = HugeIcons.strokeRoundedSecurityCheck;
  static const MyazaIconData slidersHorizontal =
      HugeIcons.strokeRoundedSlidersHorizontal;
  static const MyazaIconData smartphone = HugeIcons.strokeRoundedSmartPhone01;
  static const MyazaIconData stamp = HugeIcons.strokeRoundedStamp;
  static const MyazaIconData sun = HugeIcons.strokeRoundedSun01;
  static const MyazaIconData timer = HugeIcons.strokeRoundedTimer01;
  static const MyazaIconData triangleAlert = HugeIcons.strokeRoundedAlert01;
  static const MyazaIconData type = HugeIcons.strokeRoundedText;
  static const MyazaIconData upload = HugeIcons.strokeRoundedUpload01;
  static const MyazaIconData user = HugeIcons.strokeRoundedUser;
  static const MyazaIconData userRound = HugeIcons.strokeRoundedUserCircle;
  static const MyazaIconData userRoundPlus = HugeIcons.strokeRoundedUserAdd01;
  static const MyazaIconData usersRound = HugeIcons.strokeRoundedUserGroup;
  static const MyazaIconData videoOff = HugeIcons.strokeRoundedVideoOff;
  static const MyazaIconData x = HugeIcons.strokeRoundedCancel01;
  static const MyazaIconData zap = HugeIcons.strokeRoundedFlash;
  static const MyazaIconData zapOff = HugeIcons.strokeRoundedFlashOff;
}
