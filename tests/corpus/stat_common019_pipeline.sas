/* expect-rc: 1 (the CLUSTER tie WARNING, p.2509)
 * STAT-COMMON-019: the PROC DISTANCE -> PROC CLUSTER distance contract on
 * invented points A(0,0) B(1,2) C(4,0) D(4,3). Every expected value is hand
 * arithmetic, never opensas output.
 * - OUT= of a distance method is TYPE=DISTANCE (p.2757), so CLUSTER reads it
 *   as a distance matrix without a TYPE= data set option (p.2488); a DATA
 *   step copy loses the type and needs (TYPE=DISTANCE) again (p.2489).
 * - Not every proximity is Euclidean: CITYBLOCK gives AB=3 AC=4 AD=7 BC=5
 *   BD=4 CD=3, mean 26/6=4.333333; AB and CD tie at 3, so single linkage
 *   merges AB first (minimum larger id), flags T, then CD at 3/4.333=0.6923,
 *   then the two at 4/4.333=0.9231. EUCLID (sqrt5, 4, 5, sqrt13, sqrt10, 3;
 *   mean 3.500649) has no tie: 0.6388, 0.8570, sqrt10/mean=0.9033.
 * - Scaling: STD=RANGE divides x by 4 and y10=10*y by 30, so the square
 *   CITYBLOCK matrix equals the one for y/3: AB=11/12 BC=17/12 BD=13/12,
 *   AC=CD=1, AD=2; SHAPE=SQUARE rows equal columns (symmetry).
 * - CHEBYCHEV on the same scaled data: AB=2/3, AC=AD=CD=1, BC=BD=3/4 (ties).
 */
options nodate nonumber nocenter linesize=160;
title; footnote;
data pts;
   input id $ x y y10;
   datalines;
A 0 0 0
B 1 2 20
C 4 0 0
D 4 3 30
;
run;
proc distance data=pts method=cityblock out=cb;
   var interval(x y);
   id id;
run;
proc contents data=cb; run;
proc cluster data=cb method=single;
   id id;
run;
proc distance data=pts method=euclid out=eu;
   var interval(x y);
   id id;
run;
proc cluster data=eu method=single;
   id id;
run;
proc distance data=pts method=cityblock shape=square out=sq;
   var interval(x / std=range) interval(y10 / std=range);
   id id;
run;
proc print data=sq noobs; format _numeric_ best12.; run;
proc distance data=pts method=chebychev shape=square out=ch;
   var interval(x y / std=range);
   id id;
run;
proc print data=ch noobs; format _numeric_ best12.; run;
data plain; set cb; run;
proc contents data=plain; run;
data typed(type=distance); set cb; run;
proc cluster data=typed method=single notie;
   id id;
run;
