/* BUG-setstmtorder (doc-finder tick293 F1): statements textually BEFORE the
   driving SET execute BEFORE its read — Language Reference: Concepts Ch.24's read happens where the
   SET statement sits, not at the top of the iteration. Pinned SAS semantics:
   - iteration 1's BEFORE sees k MISSING (the SET has not executed yet);
   - iteration 2's BEFORE sees k=1: SET-read variables are NOT reset to
     missing at the top of an iteration (Language Reference: Concepts p.562: "Variables that are
     read from a data set are not [set to missing]");
   - the final BEFORE k=2 is the EOF pass: each iteration starts at the top
     of the step, so statements before the SET run one last time with the
     retained last-read values, and the step stops when the SET reads past
     the end (Ch.23 one-to-one reading: stops at the end-of-file indicator).
   The A-E matrix is the finding's five-spelling isolation of the same root
   cause; every form must print the read values 1 then 2. */
data main; input k; datalines;
1
2
;
run;
data _null_; put 'BEFORE k=' k; set main; put 'AFTER  k=' k; run;
data _null_; length k 8;              call missing(k);  set main; put 'A k=' k; run;
data _null_; length k 8; if _n_=1 then k=99;            set main; put 'B k=' k; run;
data _null_; length k 8;              k=99;            set main; put 'C k=' k; run;
data _null_; length k 8; if _n_=1 then do; call missing(k); end; set main; put 'D k=' k; run;
data _null_; length z 8;              z=99;            set main; put 'E k=' k; run;
