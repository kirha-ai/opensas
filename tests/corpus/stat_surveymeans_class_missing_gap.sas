/* expect-rc: 2
 * STAT-SURVEYMEANS-001: missing values of a categorical (character or CLASS)
 * analysis variable. SAS 9.4 adds a Missing column to Class Level
 * Information and truncates proportion limits; not implemented, so the step
 * must fail visibly (D-009 gap). Invented data.
 */
data a;
input g $ k;
datalines;
a 1
b 2
. .
a 1
b 2
;
proc surveymeans data=a;
var g k;
class k;
run;
