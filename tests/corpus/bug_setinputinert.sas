/* BUG-setinputinert (doc-finder tick305 F2): a step with BOTH a SET and an
   INPUT made the INPUT a total silent no-op — every INPUT variable missing on
   every observation at exit 0. Language Reference: Concepts p.477 step 3: "You can use an INPUT,
   MERGE, SET, MODIFY, or UPDATE statement to read a record" — the five are
   peers; p.489: "DATA steps can use a combination of some or all of the
   sources"; Table 20.4's last row: the step stops when EOF is reached by ANY
   data-reading statement. */
data a; do i=1 to 3; output; end; run;

/* external file source */
data mix; set a; infile 'tests/corpus/includes/si_n7.txt'; input z; run;
proc print data=mix noobs; run;

/* instream source, INPUT after the SET */
data mix2; set a; input z; datalines;
7
8
9
;
run;
proc print data=mix2 noobs; run;

/* source BEFORE the SET: the INPUT reads in the pre-read prefix each
   iteration, then the driver reads */
data mix3; infile 'tests/corpus/includes/si_n7.txt'; input z; set a; run;
proc print data=mix3 noobs; run;

/* EOF on the INPUT (2 records) before EOF on the SET (3 obs) stops the step:
   2 obs, the partial third iteration is not output (Table 20.4 last row) */
data mix4; set a; input z; datalines;
7
8
;
run;
proc print data=mix4 noobs; run;

/* MERGE driver + INPUT hybrid */
data m; do id=1 to 2; v=id*10; output; end; run;
data t; do id=1 to 2; w=id; output; end; run;
data mix5; merge m t; by id; infile 'tests/corpus/includes/si_n2.txt'; input z2; run;
proc print data=mix5 noobs; run;
