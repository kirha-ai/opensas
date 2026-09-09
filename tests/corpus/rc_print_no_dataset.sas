/* DEC-abortrcvsD009 (2a57cc33, main.zig 2391) — `proc print;` with no data=
   and no last-created data set is a USER error (real SAS: "There is no default
   input data set"), D-009 rc 1, not a gap at 2.
   The golden is EMPTY on purpose — the whole program is the one bad step, so
   the rc pin is the only thing asserting anything here. Before this mechanism
   existed, such a fixture would have passed no matter what the exit code was.
   expect-rc: 1 */
proc print;
run;
