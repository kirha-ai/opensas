/* BUG-importleadingzero (GH#29, D-026): an ALL-DIGIT column with leading
   zeros types NUMERIC under PROC IMPORT — live SAS 9.4 EFI assigns informat
   best32. and reads 0001 as 1 (validated repro: contents Type=Num, print
   1/2). Pins the overturn of the old hasLeadingZero keep-char choice. */
data _null_;
  file "tests/corpus/includes/import_leadzero.csv";
  put "code,name";
  put "0001,ann";
  put "0002,bob";
run;
proc import datafile="tests/corpus/includes/import_leadzero.csv" out=t dbms=csv replace;
  getnames=yes;
run;
proc contents data=t; run;
proc print data=t; run;
