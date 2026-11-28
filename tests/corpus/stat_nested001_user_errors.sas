/* expect-rc: 1
 * STAT-NESTED-001: documented invalid input is a user error with no
 * listing: the CLASS statement is required (p.6970), VAR variables must be
 * numeric (p.6971). Invented data.
 */
options nosyntaxcheck;
data s; input g $ a y @@; datalines;
p 1 3 p 1 5 p 2 4 p 2 8
;
proc nested data=s; var y; run;
proc nested data=s; class a; var g; run;
