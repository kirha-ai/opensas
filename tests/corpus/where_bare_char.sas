/* BUG-wherebarechar (doc-finder tick291 F4): a bare CHARACTER variable as a
   WHERE predicate matched ZERO rows on all four routes — the subsetting-IF
   numeric-conversion rule (BUG-charinboolean) had been applied to WHERE.
   Pins the Language Reference: Concepts p.216 rule: "The names of character
   variables can also stand alone. SAS selects observations where the value of
   the character variable is not blank" — i.e. `where <charvar>;` returns all
   values not equal to blank, a DIFFERENT rule from IF. */
data d;
  length city $8; flag=1;
  city='Oslo'; output;
  city=' ';    output;
  city='Lima'; output;
run;
/* the p.216 bare-character predicate, all four WHERE routes */
data a; set d(where=(city)); run;
proc print data=a noobs; run;
proc print data=d noobs; where city; run;
proc sql; select * from d where city; quit;
data b; set d; where city; run;
proc print data=b noobs; run;
/* control — the explicit spelling p.216 calls equivalent */
data c; set d; where city ne ' '; run;
proc print data=c noobs; run;
/* the sharp observable: '0' is non-blank, so TRUE in WHERE — but FALSE in a
   subsetting IF (numeric conversion → 0), which must NOT have moved */
data z; length s $4; input s $; datalines;
0
q
7
;
run;
proc print data=z noobs; where s; run;
data _null_; set z; if s then put 'IF-TRUE ' s; run;
/* the p.216 numeric half (0/missing false, else true) is unchanged */
data e; length who $8; input hrs ok who $; datalines;
1 1 Ann
0 1 Bea
. 1 Cal
2 0 Dee
3 . Eve
;
run;
data _null_; set e; where hrs and ok; put 'BARENUM ' who; run;
