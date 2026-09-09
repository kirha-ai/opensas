/* QA-tick147 regression lock: INFILE reading semantics that clinical data
   depends on — DSD embedded-comma quoting, consecutive-delimiter missings,
   trailing-delimiter missing, and MISSOVER short-record handling. */
data _null_;
  infile datalines dsd;
  input name :$15. a b c;
  put name= a= b= c=;
  datalines;
"Smith, John",1,,3
"Doe, Jane",4,5,
;
run;

data _null_;
  infile datalines missover;
  input x y z;
  put x= y= z=;
  datalines;
10 20
30 40 50
;
run;
