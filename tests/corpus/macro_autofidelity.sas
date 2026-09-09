/* F12 (doc-finder tick284) automatics fidelity: &SYSDAY is the trimmed day
   name (DOWNAME. blank-pads to width 9 — a format-route artefact, SAS gives
   the trimmed name) and &SYSNCPU is the honest CPU count. %put &=name prints
   NAME=value and &SYSUSERID/&SYSHOSTNAME are seeded only when the OS env
   supplies them — both pinned in macro.zig unit tests (%put goes to the log,
   env presence varies by machine); unsourceable automatics stay loud, never a
   guessed constant. Synthetic. */
%global dayok cpuok;
%macro chk;
  %if %length(&sysday) = %length(%trim(&sysday)) %then %let dayok=yes;
  %else %let dayok=no;
  %if &sysncpu >= 1 %then %let cpuok=yes; %else %let cpuok=no;
%mend;
%chk
data _null_;
  put "SYSDAY-TRIMMED=&dayok";
  put "NCPU-OK=&cpuok";
run;
