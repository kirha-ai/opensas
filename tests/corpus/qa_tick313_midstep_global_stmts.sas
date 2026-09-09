/* QA tick312 F2 / GAP-globalpredicatemismatch — POSITIVE CONTROL: a global
   statement that top level accepts (hoisted TITLE/FOOTNOTE/OPTIONS, or the
   batch-unobservable inert set) must be accepted MID-PROC too — real SAS
   executes global statements wherever they appear. Pre-fix the PROC statement
   loops used parser.isGlobalKw as their skip predicate while the hoist used
   main.isMidStepGlobal and open code used main.isInertOpenCode — three
   disagreeing keyword lists (D-014a): GOPTIONS/SASFILE/PAGE/DM mid-PROC were
   "not supported" at exit 2 (fatal inside, harmless outside), while
   ODS/LIBNAME/FILENAME mid-PROC were silently skipped but never executed
   (a silent no-op). Now ONE layered predicate family in parser.zig:
   isMidStepSkippable = isHoistedGlobalKw ∪ isInertGlobalKw (skip == handled;
   unhoisted ODS/LIBNAME/FILENAME fail LOUD mid-PROC). UNIVARIATE gains the
   D-014 arm it never had (a legal mid-step TITLE killed the step at exit 1).
   Every listing below must render, at exit 0. */
data d; id=1; x=10; run;

proc print data=d noobs;
  title 'prt';
  goptions reset=all;
  page;
  sasfile work.d load;
  dm 'log;clear';
run;

proc transpose data=d out=t;
  goptions reset=all;
  symbol1 v=dot;
  var x;
run;
proc print data=t noobs; run;

data e; id=1; x=10; run;
proc compare base=d compare=e;
  sasfile work.d load;
run;

proc univariate data=d;
  title 'uni';
  checkpoint execute_always;
  var x;
run;

proc datasets library=work nolist;
  page;
  modify d;
  format x 8.2;
run;
quit;
proc print data=d noobs; run;
