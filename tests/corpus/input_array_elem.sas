/* GAP-inputarrayelem (Language Reference: Concepts Table 21.5 row 1, p.516: "#n or / line pointer
   control in the INPUT statement with a DO loop" — reading N records into an
   array inside a DO loop is the canonical realisation): an array-element
   reference `input v{i}` was rejected with a misleading "expected ';' after
   input", while PUT and assignment accepted the same reference. The subscript
   resolves per read (the DO-loop index moves), the array's own name never
   becomes a column, and an out-of-range subscript is a loud execution ERROR
   (mirroring the array-read/assignment paths).
   expect-rc: 1 */

/* the ticket's program: three records, one observation */
data one;
   infile datalines;
   array v{3};
   do i = 1 to 3;
      input v{i};
   end;
   drop i;
datalines;
11
22
33
;
proc print data=one; run;

/* a character array works the same way, an informat may follow the subscript —
   formatted reads take w COLUMNS, so the fields sit adjacent by width */
data _null_;
   infile datalines;
   array c{2} $ 2;
   array w{2};
   do i = 1 to 2;
      input c{i} $2. w{i} 3.;
   end;
   put "MIXED: [" c1 "][" c2 "] " w1 w2;
datalines;
ab123
cd456
;

/* PUT and assignment on the same reference (the pre-existing parity) */
data _null_;
   array v{3} (7 8 9);
   do i = 1 to 3;
      put "PARITY: v{i}=" v{i};
   end;
run;

/* out-of-range subscript: loud ERROR, the step stops, nothing further runs */
data _null_;
   infile datalines;
   array v{2};
   do i = 0 to 1;
      input v{i};
   end;
datalines;
5
6
;
data _null_;
   put "AFTER: must not print";
run;
