/* GAP-wherelow-tick291 (B) — `LIKE ... ESCAPE` is documented SAS 9.4 (SQL
   Procedure User's Guide printed p.389 syntax `sql-expression <NOT> LIKE
   sql-expression <ESCAPE character-expression>`, p.390 examples: ESCAPE
   searches for LITERAL % and _; the DATA-step WHERE has the same clause,
   Statements ref printed p.364) that opensas does not implement. It used
   to be MISDIAGNOSED: the desugar rewrote the bare LIKE and left
   `escape '!'` in the token stream, so the column validator blamed `escape`
   as a column the user never wrote — "the following columns were not found
   in the contributing tables: escape" at rc 1, the user-error class for a
   program real SAS runs clean. Now the named gap "WHERE LIKE: the ESCAPE
   clause is not supported", marked rc 2 (D-009/D-009b(i): a gap stays 2
   even though real SAS exits 0). The clean LIKE above prints, so an rc 2
   here is the gap and not a dead interpreter; the golden holds only that
   clean stdout — the ERROR is stderr-side.
   expect-rc: 2 */
data t;
  length name $20;
  input name $20.;
  datalines;
100% sure
100x sure
;
run;
proc sql;
  create table ok as select name from t where name like '100x%';
quit;
data _null_; set ok; put "ok=" name; run;
proc sql;
  select name from t where name like '100!%' escape '!';
quit;
