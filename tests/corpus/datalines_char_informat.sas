/* DATALINES-informat: a plain `$w.` informat is FORMATTED input — it reads the
   full w columns including embedded blanks, not a whitespace token. The `:$w.`
   colon form stays LIST input (token, then truncate to w). A `$w.` after a plain
   `$` list read starts at the cursor just past that token. */
data fixed;
  input t $20.;
  datalines;
AAA; BBB
CCC DDD EEE
;
run;
data _null_; set fixed; n=length(t); put "FIXED=[" t "] len=" n; run;

data listform;
  input t :$20.;
  datalines;
AAA; BBB
CCC DDD EEE
;
run;
data _null_; set listform; n=length(t); put "LIST=[" t "] len=" n; run;

data mixed;
  input id $ name $12.;
  datalines;
01 John Smith
02 Jane Doe
;
run;
data _null_; set mixed; put "MIX id=[" id "] name=[" name "]"; run;
