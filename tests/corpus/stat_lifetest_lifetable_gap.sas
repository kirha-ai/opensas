/* expect-rc: 2
 * STAT-LIFETEST-003: the life-table method is implemented for one sample
 * with explicit INTERVALS= only. Without INTERVALS= the number of default
 * intervals is not settled by the guide, so the step must fail visibly
 * (D-009 gap) without printing a partial analysis. Invented data.
 */
data spells;
input months ended n;
datalines;
1 1 4
2 0 2
3 1 3
5 0 1
;
run;
proc lifetest data=spells method=lt;
time months*ended(0);
freq n;
run;
