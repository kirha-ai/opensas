/* expect-rc: 1
 * STAT-STDIZE-003: boundary and invalid METHOD= arguments and METHOD=IN
 * inputs. Each step is a user error in SAS 9.4 (verified, invented data):
 *   ABW(-1)            ERROR: The value of METHOD= ABW(), AHUBER() or AWAVE() must be greater than zero.
 *   SPACING(0)/AGK(0)  ERROR: The value of METHOD  = AGK() or METHOD  = SPACING() must be greater than zero.
 *   AGK(0.01), n = 10  ERROR: ... AGK() is too small to have at least one pair.
 *   ABW without (c)    ERROR 79-322: Expecting a (.
 *   IN, VAR not in ds  ERROR: Variable w is not found in the METHOD= IN() data set.
 *   IN without _TYPE_, no LOCATION/SCALE statements, LOCATION count mismatch,
 *   LOCATION without METHOD=IN -- each an ERROR; nothing is printed.
 */
options nodate nonumber nocenter linesize=120;
data a;
input x y w @@;
datalines;
1 10 1 2 12 2 3 11 1 4 15 3 5 14 1 7 13 2 9 30 1 12 16 1 20 18 2 6 17 1
;
proc stdize data=a method=abw(-1) pstat; var x; run;
proc stdize data=a method=spacing(0) pstat; var x; run;
proc stdize data=a method=agk(0) pstat; var x; run;
proc stdize data=a method=agk(0.01) pstat; var x; run;
proc stdize data=a method=abw pstat; var x; run;
data ins;
input _type_ $ x y;
datalines;
LOCATION 2 10
SCALE 4 5
;
proc stdize data=a method=in(ins) pstat; var x w; run;
data ls;
input lx ly sx sy;
datalines;
2 10 4 5
;
proc stdize data=a method=in(ls) pstat; var x y; run;
proc stdize data=a method=in(ls) pstat; var x y; location lx; scale sx sy; run;
proc stdize data=a method=std pstat; var x y; location lx ly; scale sx sy; run;
