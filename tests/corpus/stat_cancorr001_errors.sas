/* expect-rc: 1
 * STAT-CANCORR-001: a missing WITH statement is a user error (p.2126: the
 * WITH statement is required) and prints nothing. The other user errors
 * (character or unknown VAR / WITH / FREQ / WEIGHT variables, unquoted
 * VNAME=, SINGULAR= outside (0, 1), ...) are pinned in
 * src/stat/cancorr_tests.zig through the captured reporter. Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data T;
input a b c $;
datalines;
1 2 x
2 1 y
3 4 z
4 3 w
;
proc cancorr data=T; var a; run;
