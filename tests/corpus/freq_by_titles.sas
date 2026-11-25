/* STAT-FREQ-005: full title stack, formatted BY substitutions, cancellation,
   and ordinary non-BY emission through the main FREQ dispatch. */
options nodate nonumber;
ods graphics off;
data groups;
  input Region Category $;
  label Region='Geographic Region';
  format Region z2.;
  datalines;
1 A
1 B
2 A
2 B
;
run;
title 'Study #BYVAL(Region)';
title2 '#BYVAR1 = #BYVAL1';
proc freq data=groups;
  by Region;
  tables Category / nocum;
run;
title;
proc freq data=groups;
  by Region;
  tables Category / nocum;
run;
title 'Single report';
title2 'Second line';
proc freq data=groups;
  tables Category / nocum;
run;
