%macro whisper(msg);
data _null_; put "psst &msg";
run;
%mend whisper;
