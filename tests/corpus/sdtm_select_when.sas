/* Map severity code to grade with a SELECT-WHEN block (DATA step) */
data ae;
  input USUBJID $ AESEV $;
  datalines;
01-001 MILD
01-002 SEVERE
01-003 MODERATE
;
run;
data graded;
  set ae;
  length grade 8;
  select (AESEV);
    when ("MILD") grade = 1;
    when ("MODERATE") grade = 2;
    when ("SEVERE") grade = 3;
    otherwise grade = .;
  end;
run;
proc print data=graded; run;
