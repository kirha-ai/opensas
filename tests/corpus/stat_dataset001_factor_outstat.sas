/* STAT-DATASET-001: PROC FACTOR OUTSTAT= writes a TYPE=FACTOR special data set
 * (S154 pp.10880-10881, Table A.2): _TYPE_/_NAME_ character length 8 with
 * their labels, then the analysis variables; rows MEAN STD N CORR(x3)
 * COMMUNAL PRIORS EIGENVAL PATTERN(x2). Data, listing and every value below
 * come from the SAS 9.4 reference run of this analysis (STAT-DATASET-001
 * native_contract); values printed at the reference's 4 decimals. Invented data.
 */
options nodate nonumber nocenter linesize=160;
data sample;
 input x z y group $ weight freq;
 datalines;
1 1 4 A 1 1
2 1 6 A 2 1
3 2 7 A 1 2
4 1 9 A 1 1
5 3 13 A 2 1
6 2 12 A 1 1
7 4 17 B 1 1
8 3 19 B 2 2
9 5 20 B 1 1
10 3 23 B 1 1
11 5 25 B 2 1
12 4 24 B 1 1
;
run;
proc factor data=sample method=principal nfact=2 outstat=structure; var x z y; run;
data _null_;
  file print;
  length t $16 vn $8 vl $40 vt $1;
  h = open('structure');
  t = attrc(h, 'TYPE'); n = attrn(h, 'NOBS'); v = attrn(h, 'NVARS');
  put 'TYPE=' t 'NOBS=' n 'NVARS=' v;
  do k = 1 to v;
    vn = varname(h, k); vt = vartype(h, k); vl = varlabel(h, k); len = varlen(h, k);
    put @1 k 1. @3 vn $8. @12 vt $1. @14 len 1. @16 vl;
  end;
  rc = close(h);
run;
data _null_;
  file print;
  set structure;
  put @1 _type_ $8. @10 _name_ $8. @19 x 8.4 @28 z 8.4 @37 y 8.4;
run;
