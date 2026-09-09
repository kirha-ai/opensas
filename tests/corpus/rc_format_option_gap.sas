/* GAP-gapsexitingone §5b re-verdict — MAXLABLEN= is a documented SAS 9.4
   PROC FORMAT statement option (Summary of Optional Arguments, Procedures
   Guide 7th ed. printed p. 1085) opensas does not implement — an opensas
   gap, exit 2. Typo twin: rc_format_option_typo.sas. expect-rc: 2 */
proc format maxlablen=8;
  value f 1='a';
run;
