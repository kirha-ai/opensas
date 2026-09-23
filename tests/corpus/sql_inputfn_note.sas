/* GAP-sqlinputfnnote: the INFORMAT= column-attribute coercion (INSERT VALUES /
   UPDATE SET — sql.zig coerceToColumn) shares functions.readInformat with the
   INPUT() function but bypassed its dispatch guard, so after GH#5 an unknown
   informat fired the loud "was not found or could not be loaded" ERROR and
   stored MISSING with no invalid-data NOTE. Language Reference: Concepts
   p.518 "How SAS Handles Invalid Data": the value is MISSING (pinned by the
   select below) and the invalid-data NOTE prints — the same text the INPUT()
   function dispatch prints, because the coercion models the INPUT()
   function's exact semantics (GAP-sqlcolumnattr). Action 3 (_ERROR_=1) is a
   DATA-step PDV automatic with no PROC SQL row sink — a select result is a
   table, not an observation — so NOTE + missing is the whole contract here.
   The probe with a KNOWN informat (8. reading 'abc') notes the same way with
   no ERROR. Diagnostics ride stderr, so this stdout golden pins the missing
   values and the steps completing; the NOTE text itself is pinned by sql.zig's
   captured-diagnostics tests. Invented data.

   expect-rc: 1 */
proc sql;
  create table bad (n num informat=zzznotreal.);
  insert into bad values ('2025');
  select * from bad;
quit;
run;
proc sql;
  create table ok (n num informat=8.);
  insert into ok values ('2025');
  insert into ok values ('abc');
  select * from ok;
quit;
run;
