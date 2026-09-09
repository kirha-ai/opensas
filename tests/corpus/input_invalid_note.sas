/* NOTE-inputinvalidnote (Language Reference: Concepts p.518 "How SAS Handles Invalid Data" — FOUR
   mandated actions): the INPUT statement performed only action 1 (value →
   missing). Now the statement path also performs action 2 (the invalid-data
   NOTE, with the REAL record line and column — the house text's hardcoded
   0/0 belongs to the no-span expression path) and action 3 (_ERROR_=1 for the
   current observation), so the `if _error_ then …` validation idiom works on
   INPUT again. `?` suppresses the NOTE, `??` also suppresses _ERROR_.
   Action 4's record-echo + printed scale are NOT implemented (the numbers are
   in the NOTE text, on stderr). The INPUT() function path stays silent —
   `input(x, ?? fmt.)` suppression cannot be threaded through the generic
   argument parser yet (reported in the ticket, not claimed closed).
   stdout pins _ERROR_; the NOTE text is asserted by an in-file test. */
data _null_;
   input x y;
   put "STMT: x=" x " y=" y " _ERROR_=" _ERROR_ " _N_=" _n_;
datalines;
J23 5
10 20
;

/* informat-nonconformance (p.518's second definition of invalid) */
data _null_;
   input dt mmddyy10.;
   put "NONCONF: dt=" dt " _error_=" _error_;
datalines;
notadate!!
;

/* `??` suppresses the note AND _ERROR_; `?` suppresses the note only */
data _null_;
   input x ?? y;
   put "QQ: x=" x " y=" y " _ERROR_=" _error_;
datalines;
J23 5
;
data _null_;
   input x ? y;
   put "Q: x=" x " y=" y " _ERROR_=" _error_;
datalines;
J23 5
;

/* delimited and column-range reads note the same way (stdout: _ERROR_ only) */
data _null_;
   infile datalines dlm=',';
   input a b;
   put "DLM: a=" a " b=" b " _ERROR_=" _error_;
datalines;
xy,2
;
data _null_;
   input a 1-3 b 5-6;
   put "COL: a=" a " b=" b " _ERROR_=" _error_;
datalines;
J23 45
;
