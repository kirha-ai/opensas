/* GAP-libnameopt + GAP-filenameopt (tick330 EBNF audit, Phase-G): LIBNAME's
   option list and FILENAME's trailing name=value options gained a real final
   else (D-002) — a typo like `acces=readonly` / `lrelc=100` used to vanish at
   exit 0 (the LIBNAME typo even left the lib UNPROTECTED: the old scan matched
   the bare word "readonly" anywhere, hiding the typo while binding read-write).
   POSITIVE CONTROL, the important half: honoured options (ACCESS=TEMP binds
   read-write; ACCESS=READONLY still reads fine) and the legitimately-inert
   piles (COMPRESS=/REUSE= — on-disk storage properties; LRECL=/TERMSTR=/
   RECFM=V — the full-line reader observes none of them) must keep binding,
   registering, and READING at exit 0. The loud arms (bogusopt=, acces=,
   access=bogus, lrelc=, recfm=f) are pinned by the captured-diagnostics test
   in src/main.zig — never a real aborting process. */
libname g "tests/corpus/includes/gsopt" access=temp compress=yes reuse=no;
libname gro "tests/corpus/includes/gsopt" access=readonly compress=char;
filename gf "tests/corpus/includes/gsopt/members.csv" lrecl=32767 termstr=crlf recfm=v;
data via_lib;
  set gro.members; /* read through the READONLY binding — reads stay permitted */
run;
data via_file;
  infile gf dsd missover firstobs=2;
  input site $ sbj $ age;
run;
proc print data=via_lib noobs;
run;
proc print data=via_file noobs;
run;
