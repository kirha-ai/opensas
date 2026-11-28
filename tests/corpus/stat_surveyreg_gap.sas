/* expect-rc: 2
 * STAT-SURVEYREG-001: a DOMAIN analysis is documented but not implemented;
 * the step must fail visibly (D-009 gap) without printing a listing.
 * Invented data.
 */
data visits;
input region x y;
datalines;
1 1 11
1 2 13
2 3 12
2 4 16
;
proc surveyreg data=visits;
model y = x;
domain region;
run;
