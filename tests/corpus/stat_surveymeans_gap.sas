/* expect-rc: 2
 * STAT-SURVEYMEANS-001: a DOMAIN analysis is documented but not implemented;
 * the step must fail visibly (D-009 gap) without printing a listing.
 * Invented data.
 */
data visits;
input region y;
datalines;
1 11
1 13
2 12
2 16
;
proc surveymeans data=visits;
var y;
domain region;
run;
