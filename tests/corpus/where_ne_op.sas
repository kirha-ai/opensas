/* BUG-wherene (QA-audit42): inside a WHERE expression `<>` means NOT-EQUAL —
   the documented SAS WHERE quirk — not the Group-I MAX operator. All three
   routes: WHERE statement, where= dataset option, PROC WHERE. The option route
   also proves serializeParens round-trips the `<>` token (tokenText dropped it
   to "" and the filter silently kept every row). */
data a; do x = 1 to 5; output; end; run;

data b; set a; where x <> 3; run;
data _null_; set b end=eof; if eof then put "STMT n=" _n_; run;

data c; set a(where=(x <> 3)); run;
data _null_; set c end=eof; if eof then put "OPT n=" _n_; run;

proc print data=a; where x <> 3; run;
