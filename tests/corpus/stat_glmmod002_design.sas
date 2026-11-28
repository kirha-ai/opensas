/* expect-rc: 0
 * STAT-GLMMOD-002: design matrix construction for model effects on a small
 * invented data set whose columns are checked by hand (S154 pp.4232-4236):
 * intercept, CLASS main effect, covariate, polynomial x*x, continuous-by-class
 * x*a and nested b(a) columns, the OUTDESIGN= values and OUTPARM= rows.
 * Hand calculation (row: Col1..Col11 = 1, a=p, a=q, x, x*x, x*[a=p], x*[a=q],
 * [b=1,a=p], [b=2,a=p], [b=1,a=q], [b=2,a=q]):
 *   p 1 x=0.5  -> 1 1 0  0.5  0.25   0.5 0     1 0 0 0
 *   q 1 x=1.25 -> 1 0 1  1.25 1.5625 0   1.25  0 0 1 0
 *   p 2 x=2    -> 1 1 0  2    4      2   0     0 1 0 0
 *   q 2 x=-1   -> 1 0 1 -1    1      0  -1     0 0 0 1
 *   p 1 x=3    -> 1 1 0  3    9      3   0     1 0 0 0
 *   q 1 x=0.1  -> 1 0 1  0.1  0.01   0   0.1   0 0 1 0
 * Then the Design Points precision convention: each column gets the w.d
 * format whose d is the most decimals any value asks for (exact, but at most
 * three significant digits) and whose w is the widest value; w > 8 gives E8.2.
 * Expected listing: SAS 9.4 (SAS/STAT 15.4) run of these steps, 2026-11-28,
 * compared token by token (whitespace-normalised). Invented data.
 */
options nodate nonumber nocenter linesize=200 pagesize=max;
title 'G2 small design';
data s;
input a $ b x y;
datalines;
p 1 0.5 3.2
q 1 1.25 4.75
p 2 2 5
q 2 -1 2.5
p 1 3 7.125
q 1 0.1 1
;
proc glmmod data=s outdesign=d outparm=pp;
class a b;
model y = a x x*x a*x b(a);
run;
proc print data=d; run;
proc print data=pp; run;
title 'G2 precision';
data r;
input c1-c19 z1-z3;
datalines;
3.2 0.333333333333 2.123456789 1 123.456 1234567.5 0.001 99999 12345.678 0.123456 -0.5 1000000 0.0000001 1.5 33.3333333 0.05 1234567.5 123456789 9.996 0.5 1000 0.001
4.75 0.00012 -3.5 2 1 0.25 1 0.5 1 0.5 -12.25 1 1 1.5 1 1 0 1 1 1.5 2000 0.002
5 12 7 3 1 100 1 1 1 1 1 1 1 1.5 1 1 1 1 1 2.25 3000 0.003
2.5 2.5 0.1 4 1 1 1 1 1 1 1 1 1 1.5 1 1 1 1 1 -3 4000 0.004
;
proc glmmod data=r;
model c1-c19 = z1 z2 z3;
run;
