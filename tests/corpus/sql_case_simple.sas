data d;
  input grade $;
  datalines;
A
B
C
;
run;

proc sql;
  create table t as
    select grade, case grade when "A" then 4 when "B" then 3 else 0 end as gpa
    from d;
quit;

data _null_;
  set t;
  put "grade=" grade " gpa=" gpa;
run;
