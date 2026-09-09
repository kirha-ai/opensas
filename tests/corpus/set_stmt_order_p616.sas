/* Pins the Language Reference: Concepts Ch.24 p.616 (PDF 634) hash lookup-join
   rule ("Loading a Data Set and Using the FIND Method to Retrieve Data",
   Example 2), including the p.613-prescribed `call missing(<key>, <data>);`
   ("Use the CALL MISSING routine with all the key and data variables as
   parameters" — one of the three sanctioned remedies for uninitialized
   variable notes). A three-row lookup table is loaded into the hash on
   _N_=1, then every key of a three-row probe table is looked up with FIND.
   BUG-setstmtorder: the priming block runs BEFORE the SET's read, so
   `call missing` no longer wipes the key the SET just fetched — the
   documented result is ALL THREE probe rows matched (7 70 / 8 80 / 9 90);
   the pre-fix order silently dropped the first observation at exit 0. */
data rates; input code pct; datalines;
7 70
8 80
9 90
;
run;
data probes; input code; datalines;
7
8
9
;
run;
data joined;
   length code 8;
   length pct 8;
   if _N_ = 1 then do;
      declare hash h(dataset: "work.rates");
      h.defineKey('code');
      h.defineData('pct');
      h.defineDone();
      call missing(code, pct);
   end;
set probes;
rc = h.find();
if (rc = 0) then output;
run;
proc print data=joined noobs;
   title 'Hash FIND lookup join (Concepts p.616 rule)';
run;
