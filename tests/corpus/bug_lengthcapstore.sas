/* BUG-lengthcapnostore regression guard on 67a3c834: the WITH-A-STORE case
   was already loud (pdv.setAt cap, first store). The statement-side check
   now fires one step earlier (parse, not store) with the same message text;
   the observable behaviour is unchanged: ERROR + NOTE on the log, exit 1,
   and the step after the bad declaration never runs. Pins that moving the
   rejection earlier did not weaken 67a3c834's route.
   expect-rc: 1 */
data _null_; put 'CONTROL'; run;
data a; length x $40000; x='hi'; run;
data _null_; put 'STORED SILENTLY — REGRESSED'; run;
