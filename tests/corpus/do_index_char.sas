/* BUG-doindexchar: a value-list DO index compiles to the FIRST do-list
   value's type. `do a1="NONE";` in a DEAD branch must leave a1 CHAR missing
   (blank), not numeric missing — gen2 AE's AEACNOTH1/2/3 are assigned exactly
   this way, and the numeric guess rendered "Z.." trailing dots on every
   non-MULTIPLE row. */
data t;
  x = 2;
  if x = 1 then do a1 = "NONE"; cpt = 1; end;
  if x = 3 then do a2 = "MULTIPLE"; cpt = 2; end;
  z = "[Z" || a1 || a2 || "]";
  put z=;

  /* executed char do-list still iterates its values */
  if x = 2 then do w = "A", "B"; s = s || w; end;
  put s=;

  /* numeric value-list index stays numeric, dead or alive */
  if x = 9 then do n1 = 1, 3; end;
  do n2 = 5, 7; end;
  nt = "[" || vtype(n1) || vtype(n2) || "]";
  put nt=;
run;
