/* expect-rc: 2
 * STAT-DATASET-001: special-input consumers do not yet read the TYPE= attribute,
 * so a typed data set given to one of them must fail visibly (D-009 gap), never
 * be analysed silently as raw data. Invented data.
 */
data a; input x y z; datalines;
1 2 3
2 1 5
3 4 4
4 3 8
5 6 7
;
data e(type=corr); set a; run;
proc factor data=e; run;
