abstract final class Formatters {
  static String currency(num value, {String symbol = 'Q'}) {
    final parts = value.toStringAsFixed(2).split('.');
    final whole = parts.first;
    final isNegative = whole.startsWith('-');
    final digits = isNegative ? whole.substring(1) : whole;
    final buffer = StringBuffer();

    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }

    return '${isNegative ? '-' : ''}$symbol$buffer.${parts.last}';
  }

  static String dateTime(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');

    return '${twoDigits(local.day)}/${twoDigits(local.month)}/${local.year} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}
