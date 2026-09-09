/* GAP-gapsexitingone §5b re-verdict — FMTLIB is a documented SAS 9.4 PROC
   FORMAT statement flag (printed p. 1085) opensas does not implement — an
   opensas gap, exit 2. Typo twin: rc_format_flag_typo.sas. expect-rc: 2 */
proc format fmtlib;
run;
