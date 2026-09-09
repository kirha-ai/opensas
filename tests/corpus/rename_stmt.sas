/* G-falsemarkers2: statement-form RENAME (`rename old=new …;`) renames output
   variables — the declarative counterpart of the `rename=(…)` dataset option
   (the EBNF marks rename_stmt (* opensas *) but only the option form worked). */
data have; a=1; b=2; c=3; output; a=4; b=5; c=6; output; run;
data want; set have; rename a=alpha c=gamma; run;
proc print data=want; run;
