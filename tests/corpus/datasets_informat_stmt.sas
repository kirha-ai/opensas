/* GAP-datasetsinformatstmt: the MODIFY-level INFORMAT STATEMENT, parity with
   the FORMAT statement arm (it used to hit the loud "sub-statement informat
   is not supported" else). Base SAS 9.4 Procedures Guide 7th ed. printed
   p.640 (pdf 690): "INFORMAT variable-1 <informat-1> <variable-2
   <informat-2> …>;" and, with no informat, the statement "removes any
   existing informats for the variables in variable-list".
   Pins: ONE trailing spec applies to EVERY listed var (a and b get 8.2), a
   spec-less statement strips (c loses COMMA8.), and a var the statement
   never lists keeps its informat (d keeps BEST12.) — while the Format
   column stays as the DATA step left it throughout. CONTENTS pins the
   Informat column. The loud paths (unknown variable rc 1, statement outside
   a MODIFY RUN group rc 2) live in proc.zig's unit test. */
data m;
  a = 1; b = 2; c = 3; d = 4;
  informat a comma8.;
  informat b best12.;
  informat c comma8.;
  informat d best12.;
  format b dollar8.;
run;
proc datasets lib=work nolist;
  modify m;
  informat a b 8.2;
  informat c;
quit;
proc contents data=m; run;
