/* STAT-KRIGE2D-001: BY groups, the missing VAR= rule, MINPOINTS= /
   MAXPOINTS= radius adjustment rows and OUTEST= with the BY variable after
   STDERR. Expected listing = a SAS 9.4 reference run of this program,
   except that the BY line uses opensas's shared centered BY-line layout
   (SAS under NOCENTER prints it flush left; a Base listing difference).
   The PUT lines are the reference run's BEST16. values rounded.
   Data: invented. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'Spatial Prediction With Kriging';
data small; input g x y z; datalines;
1 0 0 1
1 1 0 2
1 0 1 3
1 1 1 4
1 3 3 9
2 0 0 5
2 2 0 7
2 1 1 .
;
proc krige2d data=small outest=e2;
coordinates xc=x yc=y;
predict var=z radius=1.2 minpoints=2 maxpoints=3;
model scale=2 range=1 form=gau;
grid x=0.5,4 y=0.5;
by g;
run;
title;
data _null_;
set e2;
file print;
put g 2. label $13. varname $2. gxc 4.1 gyc 4.1 npoints 3. estimate 13.8 stderr 13.8;
run;
