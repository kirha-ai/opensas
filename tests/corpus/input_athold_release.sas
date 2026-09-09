/* BUG-atholdhang: single trailing `@` hold + conditional re-read where a
   branch reads no further INPUT. SAS releases an un-consumed `@` hold at the
   iteration boundary and the next INPUT reads a NEW record — opensas used to
   re-read the held line forever (hang). Must read all rows and terminate. */
data held;
  input type $ @;
  if type = 'A' then input v;
  put "type=" type "| v=" v;
datalines;
A 10
B
A 30
;
run;
