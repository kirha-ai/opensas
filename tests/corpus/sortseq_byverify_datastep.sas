/* BUG-sortseq-byverify-datastep: the DATA-step SET/BY sortedness verify must
   use the SAME collation the sort used (Language Reference: Concepts printed
   p.533 Note). The repro shape: `options sortseq=linguistic;` + PROC SORT puts
   GRP in dictionary order (A a b B c); the DATA step `set s; by grp;` then
   verifies that order. The byte-comparing SET guard read it as "BY variables
   are not properly sorted" at rc 1 and BUG-errhalt skipped every later step —
   a valid SAS program rejected. Post-fix the whole run is rc 0; the listing
   pins the rows in linguistic order (byte order would be A B a b c) and the
   first./last. flags pin byte-exact GROUPING (five separate groups — the
   fold-equal neighbours A/a and B/b never merge). Invented data.

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

data o;
  set s;
  by grp;
  fst = first.grp;
  lst = last.grp;
run;

data _null_;
  set o;
  put grp= x= fst= lst=;
run;

data _null_;
  put 'later-step-ran';
run;
