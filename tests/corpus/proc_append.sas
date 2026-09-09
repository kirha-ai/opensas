/* FEAT-procappend: PROC APPEND adds DATA= rows onto BASE= IN PLACE; the step
   itself lists nothing. Without FORCE an extra DATA= variable ERRORs and
   nothing is appended; FORCE drops it with a warning (SAS 9.4 PROC APPEND).
   Two-level work. names resolve to the WORK member. */
data a; id=1; x=10; output; id=2; x=20; output; run;
data b; id=3; x=30; output; run;
proc append base=work.a data=work.b; run;
proc print data=a noobs; run;
data c; id=9; x=90; y="dropped"; run;
proc append base=a data=c force; run;
proc print data=a noobs; run;
