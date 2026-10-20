/* Control for BUG-importleadingzero (GH#29, D-026): a MIXED column
   (0001/12/abc) stays CHARACTER — `abc` forces it — while an all-digit
   zero-padded column goes NUMERIC. Live SAS and the old keep-char choice
   agree on the mixed case; this pins that the GH#29 fix did not overreach. */
data _null_;
  file "tests/corpus/includes/import_leadzero_mixed.csv";
  put "code,name";
  put "0001,ann";
  put "12,bob";
  put "abc,cid";
run;
proc import datafile="tests/corpus/includes/import_leadzero_mixed.csv" out=m dbms=csv replace;
  getnames=yes;
run;
proc contents data=m; run;
proc print data=m; run;
