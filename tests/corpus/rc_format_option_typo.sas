/* GAP-gapsexitingone §5b re-verdict — a TYPO'd PROC FORMAT option
   (`mxlablen=8`) is the USER's error, exit 1. The Summary of Optional
   Arguments closes the option set, so the catch-all can tell a typo from
   an unimplemented option; the gap twin pins MAXLABLEN= at rc 2.
   expect-rc: 1 */
proc format mxlablen=8;
  value f 1='a';
run;
