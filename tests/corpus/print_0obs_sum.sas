/* BUG-print0obssum: a 0-observation input must NOT emit a phantom SUM grand
   total (`= 0`) — SAS prints no table at all (only a "No observations" NOTE).
   opensas keeps the bare header per the tick155 0-obs decision, but the total
   line (and the naked BY `=`/`0`) is gone. A non-empty PRINT+SUM is unchanged. */
data empty;
  input g x;
  datalines;
;
run;

proc print data=empty; sum x; run;

proc print data=empty; by g; sum x; run;

proc print data=empty; run;

data full;
  input g x;
  datalines;
1 10
2 20
;
run;

proc print data=full; sum x; run;
