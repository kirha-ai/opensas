/* GAP-gapsexitingone §5c — `MODIFY ds POINT=var;` is Form 3 of the MODIFY
   statement (SAS 9.4 Statements ref, printed p.240-241); `END=` is on Forms
   1/2/4. Both are documented arguments opensas's MODIFY driver does not
   implement, so the refusal is an opensas GAP → rc 2, not rc 1.

   No typo can reach this guard: the parser rejects any other `name=` option
   on a MODIFY at rc 1 before exec ever sees it, and the `\x00prefix=` list
   sentinel is expanded away earlier — only end=/point= arrive here.

   The PROC PRINT proves plain MODIFY still works, so this is a POINT=-shaped
   gap and not a blanket MODIFY rejection. One error, last (BUG-errhalt).
   expect-rc: 2 */
data a;
  input x;
  datalines;
1
2
;
run;

data a;
  modify a;
  x = x * 10;
run;

proc print data=a noobs;
run;

data a;
  modify a point=p;
run;
