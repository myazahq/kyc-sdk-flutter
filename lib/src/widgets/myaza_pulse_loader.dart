import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'myaza_spinner.dart';

/// The SDK's larger loading indicator. It used to be a pulsing ring around a
/// tinted circle; it is now the one spinner every surface shares
/// (myaza_spinner.dart), centred in the same box so no screen's layout moves.
/// The name is kept because several screens mount it.
class MyazaPulseLoader extends StatelessWidget {
  /// The box the loader sits in. The spinner fills a small box and half of a
  /// large one.
  final double size;

  const MyazaPulseLoader({super.key, this.size = 80});

  /// The spinner's side for a loader box: all of a small box, half of a large
  /// one (80 gives 40, 64 the web's 32).
  static double spinnerSize(double box) => box <= 32 ? box : (box / 2).roundToDouble();

  @override
  Widget build(BuildContext context) {
    final side = spinnerSize(size);
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: SizedBox(
          width: side,
          height: side,
          child: MyazaSpinner(color: context.myazaColors.primary),
        ),
      ),
    );
  }
}
