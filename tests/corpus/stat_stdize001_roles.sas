/* STAT-STDIZE-001: FREQ, WEIGHT, VARDEF=, ADD=/MULT=, NOMISS, REPLACE,
 * REPONLY, MISSING= and the closed-form METHOD= measures of Table 115.2 on
 * an invented sample (x = 1, 2, 3, 6 with one missing y). Expected values are
 * hand arithmetic:
 *   FREQ f (1,1,2,1): x mean 15/5 = 3, CSS 14, std sqrt(14/4);
 *   WEIGHT w (1,2,1,1), METHOD=SUM: scale 1+4+3+6 = 14;
 *   METHOD=RANGE ADD=10 MULT=2: 10 + 2(x-1)/5;
 *   METHOD=IQR (PCTLDEF=5): median 2.5, Q3-Q1 = 4.5-1.5 = 3;
 *   METHOD=MAD: median |x-2.5| = 1; METHOD=MIDRANGE: (x-3.5)/2.5;
 *   METHOD=MAXABS: x/6; METHOD=EUCLEN: x/sqrt(50); METHOD=USTD VARDEF=N:
 *   x/sqrt(50/4).
 */
options nodate nonumber nocenter linesize=120;
data d;
input x y f w;
datalines;
1 4 1 1
2 . 1 2
3 8 2 1
6 0 1 1
;
proc stdize data=d out=o1 replace; var x y; freq f; run;
proc stdize data=d out=o2 method=sum missing=-1; var x y; weight w; run;
proc stdize data=d out=o3 method=range add=10 mult=2 reponly; var x y; run;
proc stdize data=d out=o4 method=range add=10 mult=2 nomiss; var x y; run;
data all;
merge o1(rename=(x=freq_std y=freq_y_rep))
      o2(rename=(x=wsum y=wsum_ymiss))
      o3(rename=(x=reponly_x y=reponly_y))
      o4(rename=(x=range_nomiss y=range_y));
run;
proc print data=all noobs; var freq_std freq_y_rep wsum wsum_ymiss reponly_x reponly_y range_nomiss range_y; format _numeric_ 10.6; run;
proc stdize data=d out=m1 method=iqr; var x; run;
proc stdize data=d out=m2 method=mad; var x; run;
proc stdize data=d out=m3 method=midrange; var x; run;
proc stdize data=d out=m4 method=maxabs; var x; run;
proc stdize data=d out=m5 method=euclen; var x; run;
proc stdize data=d out=m6 method=ustd vardef=n; var x; run;
data methods;
merge m1(keep=x rename=(x=iqr)) m2(keep=x rename=(x=mad)) m3(keep=x rename=(x=midrange))
      m4(keep=x rename=(x=maxabs)) m5(keep=x rename=(x=euclen)) m6(keep=x rename=(x=ustd_n));
run;
proc print data=methods noobs; format _numeric_ 10.6; run;
