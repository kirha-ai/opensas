/* Native sas7bdat libname round-trip of the attributes that are ALREADY
   CORRECT (doc-finder tick220 verified-correct lock): 16-char name + case,
   special missing .K, IEEE extremes (1e300/1e-300 pass through raw), variable
   label + format + informat via the .labels sidecar, a $300 declared char,
   and column order. PROC COPY writes eagerly, so the second libname's
   preloaded copy comes through the sas7bdat READER, not the in-memory set. */
data src;
  length longvariablename01 8 code $8 txt $300 dt 8 sm 8 big 8 small 8;
  label code='Subject Code' dt='Visit Date';
  format dt date9.; informat code $8.;
  longvariablename01 = 1; code = 'AB'; dt = 23000; sm = .K;
  big = 1e300; small = 1e-300;
  txt = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
run;
libname L "tests/corpus/includes/s7attr";
proc copy in=work out=L;
  select src;
run;
libname R "tests/corpus/includes/s7attr";
data back; set R.src; run;
proc contents data=back; run;
data _null_; set back;
  put "sm=" sm " l01=" longvariablename01 " code=" code;
  put "big=" big best32.; put "small=" small best32.;
  put "dt=" dt;
run;
