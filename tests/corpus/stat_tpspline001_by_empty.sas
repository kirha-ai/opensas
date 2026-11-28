/* expect-rc: 1
 * STAT-TPSPLINE-001: a BY group without a usable observation (all FREQ
 * values below one, or all responses missing) is an ERROR naming the BY
 * group, and the other groups are still analysed (SAS 15.4 reference run of
 * this program; the words below are its listing). Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote; ods graphics off;
data surface;
do x1=-1 to 1 by 0.5;
do x2=-1 to 1 by 0.5;
do rep=1 to 2;
y=3+x1-2*x2+0.5*x1*x2+0.1*cos(rep+x1+x2);
output;
end;
end;
end;
run;
data k3; set surface(in=a) surface(in=b) surface(in=c); g=1+b+2*c; f=1; if g=2 then f=0; run;
title 'A middle group all freq zero';
proc tpspline data=k3; by g; freq f; model y=(x1 x2); run;
data k5; set surface(in=a) surface(in=b); g=1+b; if g=2 then y=.; run;
title 'B last group all y missing';
proc tpspline data=k5; by g; model y=(x1 x2); run;
