/* F-printlabel: PROC PRINT `label` uses the column's label in the header (falling
   back to the name for an unlabeled var); a LABEL statement inside PROC PRINT too. */
data d;
  amt = 1234.5;
  qty = 3;
  label amt = "The Amount";
run;
/* label option: amt -> "The Amount", qty -> "qty" (unlabeled) */
proc print data=d label; run;
/* no label option: header shows the names */
proc print data=d; run;
/* LABEL statement inside PROC PRINT overrides + turns label mode on */
proc print data=d noobs; label qty = "Quantity"; run;
