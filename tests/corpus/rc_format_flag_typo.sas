/* GAP-gapsexitingone §5b re-verdict — an unknown bare PROC FORMAT header
   token (`zzzq`) is the USER's error, exit 1; the documented bare flags
   (FMTLIB/LOCALE/NOREPLACE/PAGE) are the gap arm, pinned by
   rc_format_flag_gap.sas. expect-rc: 1 */
proc format zzzq;
run;
