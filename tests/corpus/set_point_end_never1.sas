/* ORACLE-unblocked-batch item 3 — SET's END= under random access. Pinned
   CONFORMANT against SAS 9.4 DATA Step Statements: Reference, SET Statement,
   printed p.332 (marker "=== pdf 343 ===", the preceding footer reads
   "SET Statement 331" and belongs to pdf 342):

     "END=variable
        creates and names a temporary variable that contains an end-of-file
        indicator. The variable, which is initialized to zero, is set to 1 when
        SET reads the last observation of the last data set listed. This
        variable is not added to any new data set.
      Restriction  END= cannot be used with POINT=. When random access is used,
                   the END= variable is never set to 1."

   Note what the second sentence of that Restriction does: it spells out that
   "cannot be used with" means THE FLAG STAYS 0, not "SAS raises an error".
   That is the same volume's own gloss on the same word for the same option, so
   it also fixes the reading of INFILE END='s parallel Restriction on p.130 —
   see docs/findings/oracle-unblocked-readings.md item 3.

   Pinned: end= is 0 on every direct-access read INCLUDING the one that reads
   the physically last observation. */
data src;
  do i = 1 to 3; v = i * 10; output; end;
run;
data _null_;
  do k = 1 to 3;
    set src point=k nobs=nn end=e;
    put "point k=" k " v=" v " end=" e;
  end;
  stop;
run;
