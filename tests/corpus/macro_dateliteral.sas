/* Date/time/datetime LITERALS ('15JAN2020'd, '12:00't, '…'dt) evaluate to their
   SAS numeric inside %sysfunc / %sysevalf, not coerce to missing. corpus-macrodateliteral. */
%let d = %sysevalf('15JAN2020'd);
%let dy = %sysfunc(day('15JAN2020'd));
%let nx = %sysfunc(intnx(month, '15JAN2020'd, 3));
%let mo = %sysfunc(month("01JAN2020"d));
%let tm = %sysevalf('12:00't);
%let dt = %sysevalf('15JAN2020:12:00:00'dt);
%let arith = %sysevalf('15JAN2020'd + 1);
data _null_;
  put "d=&d dy=&dy nx=&nx mo=&mo tm=&tm dt=&dt arith=&arith";
run;
