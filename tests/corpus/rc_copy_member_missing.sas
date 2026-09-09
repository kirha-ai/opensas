/* DEC-abortrcvsD009 (2a57cc33, main.zig 644) — SELECTing a member that is not
   there is the SAME condition exec.zig already reports at rc 1 as
   `File {s} does not exist`; the tree had already voted and this site was the
   odd one at 2. D-009 rc 1.
   `out=` binds to the corpus scratch dir (the proc_copy_rebind idiom) purely so
   the out= check passes and the MEMBER check is what fires; the copy fails
   before any write, so no file is produced there — verified by probe.
   expect-rc: 1 */
data a;
  x = 1;
run;
proc print data=a;
run;
libname o "tests/corpus/includes";
proc copy in=work out=o;
  select nosuchmember;
run;
