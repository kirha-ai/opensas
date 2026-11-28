/* expect-rc: 2
 * STAT-DISCRIM-001: valid DISCRIM features owned by later DISCRIM tickets
 * fail visibly (D-009 rc 2) with no listing: POOL=NO (quadratic), METHOD=
 * NPAR, CROSSVALIDATE, OUT=, PRIORS PROPORTIONAL, TESTCLASS, a TYPE=CORR
 * input data set (_TYPE_ variable), a singular pooled covariance matrix
 * and a numeric CLASS variable with a missing value. Invented data.
 */
options nosyntaxcheck;
data nums; input g y1 y2 @@; datalines;
1 1 2 1 2 3 1 3 3 1 2 1 2 5 4 2 6 6 2 5 5 2 7 4 3 9 1 3 8 2 3 9 3 3 10 2
;
proc discrim data=nums pool=no; class g; var y1 y2; run;
proc discrim data=nums method=npar; class g; var y1 y2; run;
proc discrim data=nums crossvalidate; class g; var y1 y2; run;
proc discrim data=nums out=scores; class g; var y1 y2; run;
proc discrim data=nums; class g; var y1 y2; priors proportional; run;
proc discrim data=nums; class g; var y1 y2; testclass g; run;
data tc; set nums; length _type_ $8; _type_ = 'MEAN'; run;
proc discrim data=tc; class g; var y1 y2; run;
data sg; set nums; y3 = y1 + y2; run;
proc discrim data=sg; class g; var y1 y2 y3; run;
data mg; set nums; if _n_ = 1 then g = .; run;
proc discrim data=mg; class g; var y1 y2; run;
