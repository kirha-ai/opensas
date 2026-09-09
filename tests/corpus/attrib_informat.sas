/* BUG-attribinformat: the ATTRIB informat= clause was parsed then DISCARDED, so
   `attrib d informat=date9.; input d;` read MISSING while the standalone INFORMAT
   statement applied. Now informat= rides onto the variable like INFORMAT does.
   (15JAN2020 = 21929, cf. informat_stmt_date.) corpus-attribinformat. */
data _null_;
  attrib d informat=date9.;
  input d;
  put "d=" d;
  datalines;
15JAN2020
;
run;
