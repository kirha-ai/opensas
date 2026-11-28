/* expect-rc: 1
 * STAT-SURVEYMEANS-001: an unknown analysis variable is a user error.
 * Invented data.
 */
data visits;
input y;
datalines;
11
13
;
proc surveymeans data=visits;
var nosuch;
run;
