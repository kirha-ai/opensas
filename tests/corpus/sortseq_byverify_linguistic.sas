/* BUG-sortseq-byverify: the BY sortedness verify must use the SAME collation
   the sort used. Language Reference: Concepts printed p.533, Note: "The BY
   statement honors the linguistic collation of sorted data when you use the
   SORT procedure with the SORTSEQ=LINGUISTIC option."

   The repro: `options sortseq=linguistic;` sorts GRP into dictionary order
   (A a b B c — case-folded, mixed-case pairs fold-equal and adjacent), then
   `proc print; by grp;` and `proc means; by grp;` verify that order. The
   byte-comparing verifier read the print side as "Data set s is not sorted in
   ascending sequence." at rc 1 and BUG-errhalt skipped every later step — a
   valid SAS program rejected. Post-fix the whole run is rc 0 and the listing
   pins the linguistic section order (byte order of the same rows would be
   A B a b c). Grouping stays byte-exact: A and a print as separate sections.

   expect-rc: 0 */
options sortseq=linguistic;
data cls;
  input grp $ x;
datalines;
b 2
B 3
c 4
A 1
a 5
;
run;

proc sort data=cls out=s;
  by grp;
run;

proc print data=s;
  by grp;
run;

proc means data=s mean;
  by grp;
  var x;
run;

data _null_;
  put 'later-step-ran';
run;
