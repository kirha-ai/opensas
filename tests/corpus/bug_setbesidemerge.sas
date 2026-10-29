/* BUG-setbesidemerge: a sequential SET beside a MERGE/UPDATE/MODIFY driver is
   an executable peer reader, not inert. Oracle: real SAS 9.4 via saspy/ODA. */
data a; input k v; datalines;
1 11
2 21
;
run;
data b; input k w; datalines;
1 100
2 200
;
run;
data meta; input factor; datalines;
7
;
run;
data meta2; input factor; datalines;
7
8
;
run;

data _null_;
  merge a b;
  by k;
  if _n_=1 then set meta;
  put "merge-if " k= v= w= factor=;
run;

data _null_;
  merge a b;
  by k;
  set meta2;
  put "merge-after " k= v= w= factor=;
run;

data _null_;
  set meta2;
  merge a b;
  by k;
  put "merge-before " k= v= w= factor=;
run;

data out;
  set meta2;
  merge a b;
  by k;
run;
proc print data=out noobs; run;

data out6;
  if 1 then set meta2;
  merge a b;
  by k;
run;
proc print data=out6 noobs; run;

data pointout;
  if _n_ > 2 then stop;
  set meta2 point=_n_;
  merge a;
run;
proc print data=pointout noobs; run;

data _null_;
  update a b;
  by k;
  if _n_=1 then set meta;
  put "update-if " k= v= w= factor=;
run;

data _null_;
  update a b;
  by k;
  set meta2;
  put "update-after " k= v= w= factor=;
run;

data _null_;
  set meta2;
  update a b;
  by k;
  put "update-before " k= v= w= factor=;
run;

data m; set a; run;
data m;
  modify m b;
  by k;
  if _n_=1 then set meta;
  put "modify-if " k= v= w= factor=;
run;

data m2; set a; run;
data m2;
  modify m2 b;
  by k;
  set meta2;
  put "modify-after " k= v= w= factor=;
run;

data m3; set a; run;
data m3;
  set meta2;
  modify m3 b;
  by k;
  put "modify-before " k= v= w= factor=;
run;
