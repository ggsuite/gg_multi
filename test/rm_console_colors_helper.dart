/// Removes all ANSI escape sequences that set console colors from [str].
String rmConsoleColors(Object str) {
  final ansiColorExpr = RegExp(r'\x1B\[[0-9;]*m');

  return str.toString().replaceAll(ansiColorExpr, '');
}
