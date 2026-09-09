/* BUG-renamestmtmultiout: statement-form RENAME reaches ALL output data sets,
   not just the first — Language Reference: Concepts Table 4.6 (p.72) "Statements: effect all output
   data sets" and Table 4.7 (p.73) "RENAME / changes name of variables in all
   output data sets" (contrasted with the RENAME= option, which is individual).
   Internal oracle: the DROP/KEEP/LABEL/FORMAT siblings already fan out. */
data p q; a=1; b=2; rename a=z; run;
proc print data=p; run;
proc print data=q; run;
