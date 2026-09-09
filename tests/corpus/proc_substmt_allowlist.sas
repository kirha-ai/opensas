/* GAP-procsubstmtswallow: PROC SORT/MEANS/FREQ/CONTENTS silently swallowed an
   unknown SUB-STATEMENT while PRINT/TRANSPOSE/SQL errored — and PROC SORT's
   own OPTION loop was loud while its STATEMENT loop was silent (one PROC, two
   policies). All four statement loops now end in a real else (D-002) behind
   the D-014a parser.isMidStepSkippable arm. This fixture is the POSITIVE
   CONTROL, the important half: every valid sub-statement — BY, WHERE (pre-BY
   in sort_where.sas, POST-BY here), CLASS/VAR, TABLES/WEIGHT — plus a hoisted
   mid-step TITLE (D-014) must keep parsing and rendering at exit 0. The loud
   arms (an unknown statement pre-BY and post-BY in SORT, and in MEANS/FREQ/
   CONTENTS, plus WHERE in CONTENTS which takes none) are pinned by the
   captured-diagnostics test in src/proc.zig — never a real aborting process.
   Mid-step FILENAME/ODS skip honestly in all four: since BUG-filenamemidstep
   they are hoisted and executed by main.segments (D-014a converged), so no
   loud arm for them — the skip and handle predicates agree. */
data d;
  input g $ x w;
  datalines;
a 1 1
a 2 1
b 3 2
b 4 2
;
run;
proc sort data=d out=s;
  title 'sort ok';
  by descending x;
  where x > 1;
run;
proc print data=s noobs; run;
proc means data=d maxdec=2;
  title 'means ok';
  class g;
  var x;
  where x > 1;
run;
proc freq data=d;
  title 'freq ok';
  tables g;
  weight w;
  where x > 1;
run;
proc contents data=d;
  title 'contents ok';
run;
