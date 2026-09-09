/* DSD boundary: a numeric field between two quoted char fields, consecutive
   delimiters yielding a missing value, and embedded delimiters inside quotes.
   Existing infile_dsd.sas covers a single quoted char field + firstobs=; this
   adds the numeric-missing (`Doe,,pending`) and two-quoted-field-per-line
   combination that DSD must handle in one pass. (QA tick135) */
data _null_;
  infile datalines dsd;
  input name $ score note : $11.;
  put "name=[" name "] score=[" score "] note=[" note "]";
  datalines;
"Smith, J",90,"top, honors"
Doe,,pending
"O'Neil",,
;
run;
