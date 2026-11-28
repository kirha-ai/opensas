/* expect-rc: 1
 * STAT-SURVEYREG-001: an unknown MODEL variable is a user error.
 * Invented data.
 */
data visits;
input x y;
datalines;
1 11
2 13
3 12
;
proc surveyreg data=visits;
model y = nosuch;
run;
