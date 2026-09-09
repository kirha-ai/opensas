/* GH#64 ISS-infilelrecl: INFILE lrecl= (logical record length) is a standard
   SAS 9.4 option. We read full lines, so lrecl has no runtime effect, but it
   must PARSE (was fail-loud "option lrecl is not supported", killing real
   real codelist-format programs). Accepted-and-ignored; unknown options
   still fail loud. (no PHI) */
data _null_;
  infile datalines dlm="," missover dsd lrecl=32767 firstobs=1;
  input a b c;
  put a= b= c=;
datalines;
1,2,3
;
run;
