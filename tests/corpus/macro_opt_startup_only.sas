/* GAP-macrooptfamily — MACRO|NOMACRO (ch.20 p.449) and BLOTKEYWORDS|
   NOBLOTKEYWORDS (p.444) are the only ch.20 options whose Valid-in line
   EXCLUDES the OPTIONS statement (configuration file / SAS invocation only),
   and real SAS matches its own doc: an OPTIONS use draws
     WARNING 11-12: SAS option MACRO is valid only at startup of the SAS
     System or startup of a SAS process. The SAS option is ignored.
   (BLOTKEYWORDS draws the same shape, WARNING 30-12) and the run continues
   with the macro facility still on — oracle probes 2026-10-31 (`options
   nomacro;` then a step: warning, step ran, macro still expanding). opensas
   honours that exact shape: warn, ignore, keep expanding. NOT a D-018 rc-2
   gap — real SAS ignores the runtime form too, so there is no unimplemented
   behavior to gap. rc 0. */
options nomacro blotkeywords;
%macro m;
  data _null_; put "MACRO-STILL-ON"; run;
%mend m;
%m
