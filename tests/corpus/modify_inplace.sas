data master;
  input id v;
  datalines;
1 10
2 20
3 30
;
run;
data trans;
  input id v;
  datalines;
2 999
;
run;
/* Matched-only MODIFY … BY: the transaction overwrites the matching master
   obs in place (unchanged behavior). An UNMATCHED transaction key is a
   different case — see modify_nomatch.sas / modify_newkey.sas. */
data master;
  modify master trans;
  by id;
run;
data _null_; set master; put "id=" id " v=" v; run;
