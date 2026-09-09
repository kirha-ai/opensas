/* GAP-secondsetstmt — SAS 9.4 DATA Step Statements: Reference, SET statement,
   printed p.341, "Example 6: Combining One Observation with Many", VERBATIM:
       data south;
          set revenue;
          if region=4;
          set expense point=_n_;
       run;
   ONE sequential driver + a SECOND SET that is a direct-access POINT= lookup
   is the reference's own canonical table-lookup idiom: the lookup does NOT
   drive — iteration, EOF detection and the implicit bottom-of-iteration
   output all follow the SEQUENTIAL driver (the example carries no STOP; Language Reference: Concepts
   p.488's POINT= no-EOF/no-implicit-OUTPUT rules scope to a POINT=-DRIVEN
   step — BUG-pointsuppressesalloutput). It used to fail LOUD ("POINT= is not
   supported on a second or nested SET source"): the BUG-nestedsetopts guard
   covered two shapes in one message, and only the TWO-direct-access-sources
   half is genuinely unsupported (opensas models ONE point source). The
   still-loud boundary — a second POINT= source, END= on the same statement,
   and the p.335 BY/WHERE-statement/WHERE=-option legs beside a driver — is
   pinned by the captured-diagnostics tests in src/exec.zig.
   Expected rows: _n_=1 reads expense obs 1 (11); _n_=2 is subsetted out
   (region=3) BEFORE the lookup; _n_=3 → obs 3 (33); _n_=4 → obs 4 (44). */
data revenue;
   input region amt;
   datalines;
4 100
3 200
4 300
4 400
;
data expense;
   input exp;
   datalines;
11
22
33
44
;

/* Example 6 exactly as printed */
data south;
   set revenue;
   if region=4;
   set expense point=_n_;
run;
proc print data=south noobs; run;

/* the same shape with an explicit OUTPUT — identical result: the automatic
   output is the DRIVER's (Language Reference: Concepts p.477 step 5), one row either way */
data south2;
   set revenue;
   if region=4;
   set expense point=_n_;
   output;
run;
proc print data=south2 noobs; run;

/* conditional lookup beside the driver: reads only at _n_=1, then the
   looked-up value RETAINS like any SET-read var (Language Reference: Concepts p.495 step 5) while
   the sequential driver finishes all 4 observations */
data cond;
   set revenue;
   if _n_=1 then set expense point=_n_;
run;
proc print data=cond noobs; run;

/* a plain extra SET beside the claimed lookup still reads via its own
   cursor: expense sequential per iteration, expense2 direct by _n_ */
data three;
   set revenue;
   set expense;
   set expense(rename=(exp=exp2)) point=_n_;
run;
proc print data=three noobs; run;
