/* expect-rc: 1
 * STAT-MODECLUS-001: documented invalid input is a user error with no
 * listing: METHOD= outside 0-6, a non-positive radius, an unknown option,
 * a character VAR variable, smoothing lists of different lengths (p.6819),
 * an unknown variable, an ID statement naming two variables, a missing
 * input data set and BY data that are not sorted (p.6825). Invented data.
 */
options nosyntaxcheck;
data pts;
input x y name $ @@;
datalines;
1 1 a 2 1 b 1 2 c 8 8 d 9 8 e 8 9 f
;
proc modeclus data=pts method=7 r=2; var x y; run;
proc modeclus data=pts method=1 r=0; var x y; run;
proc modeclus data=pts method=1 r=2 bogus; var x y; run;
proc modeclus data=pts method=1 r=2; var x name; run;
proc modeclus data=pts method=1 dr=1 2 cr=1 2 3 nosummary; var x y; run;
proc modeclus data=pts method=1 r=2; var x z; run;
proc modeclus data=pts method=1 r=2; var x y; id name x; run;
proc modeclus data=nosuch method=1 r=2; run;
proc modeclus data=pts method=1 r=2; by x; var y; run;
