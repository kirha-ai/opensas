/* BUG-whereoptunknownvar: a where= DATASET OPTION that names a variable NOT on
   the dataset used to silently yield 0 rows with no diagnostic (exit 0) — the
   unknown name eval'd to missing and dropped every row. This was ASYMMETRIC
   with the WHERE STATEMENT path, which fails loud "Variable X is not on file".
   Now the option path fails loud the same way.

   Layout mirrors the fail-loud fixtures (compare_failloud_opt): the valid
   where= steps print their filtered rows; the unknown-var step reports the
   error to stderr and emits nothing to stdout. If the silent-drop regresses,
   the unknown-var proc would append an (empty) print here and mismatch.
   expect-rc: 1 */
data d;
  input realvar;
  datalines;
1
2
3
;
run;
/* valid where= on an existing column — keeps realvar>1 (2 rows) */
data ok; set d(where=(realvar>1)); run;
proc print data=ok noobs; run;
/* rename makes the name valid — where sees the RENAMED name x (2 rows) */
data okr; set d(rename=(realvar=x) where=(x>1)); run;
proc print data=okr noobs; run;
/* unknown variable — fail loud, no output */
data bad; set d(where=(nope>1)); run;
proc print data=bad noobs; run;
