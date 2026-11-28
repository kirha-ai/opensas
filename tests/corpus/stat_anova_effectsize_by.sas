/* STAT-ANOVA-003: EFFECTSIZE over 40 random BY groups (seeded RAND normal;
 * scales 1E-4..1E4, including E-notation sums of squares below 1E-5) - the
 * evidence for the column decimal rule. Tokens checked in order against the
 * SAS 9.4 listing of this program (2026-11-28). */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data r; call streaminit(11);
do grp=1 to 40; sc=10**(mod(grp,9)-4); k=mod(grp,5);
  do A=1 to 2; do B=1 to 3; do C=1 to 2; do rep=1 to 1+(grp>20);
   y = sc*(rand('normal')*(1+k) + A*(mod(grp,3)) + B*(mod(grp,5))*0.5 + C*(mod(grp,4)=0)*3);
   output; end; end; end; end; end;
run;
ods output ModelANOVA=ma OverallANOVA=oa;
proc anova data=r; by grp; class A B C; model y = A B C / effectsize; run;
ods output close;
