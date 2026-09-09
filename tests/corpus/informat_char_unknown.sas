/* BUG-charinformatloud: an UNKNOWN/unimplemented CHARACTER informat fails loud
   (D-002) instead of silently copying the field verbatim. `input c $zzz.;`
   prints "ERROR: The informat zzz was not found or could not be loaded." to
   stderr and flags the run failed (non-zero exit).
   BUG-informatnotfoundcontinues (Language Reference: Concepts p.518) tightened the READ side: the
   step now STOPS at the unknown informat — a substituted verbatim read would
   land wrong DATA in a populated data set, worse than no data. (The WRITE
   side keeps its loud-then-fallback render: there it only mis-renders.)
   stdout therefore pins ONLY the first step below. Recognized char informats
   ($CHARw., $UPCASEw.) read exactly as before.
   expect-rc: 1 */
data _null_;
  input a $char5. b $upcase5.;
  put "a=[" a "] b=[" b "]";
datalines;
abc  xy
;
run;

data _null_;
  input c $zzz.;
  put "c=[" c "]";
datalines;
verbatim
;
run;
