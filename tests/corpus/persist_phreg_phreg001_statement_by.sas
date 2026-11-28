/* STAT-PHREG-001: PROC PHREG BY statement -- two BY groups holding the same
 * published SAS/STAT 15.4 Chapter 92 rats sample rows; each group is selected,
 * fitted and listed on its own. Expected listing is the SAS reference output.
 */
options nodate nonumber nocenter linesize=160;
title; footnote;
data Rats;
label Days ='Days from Exposure to Death';
input Days Status Group @@;
datalines;
143 1 0 164 1 0 188 1 0 188 1 0
190 1 0 192 1 0 206 1 0 209 1 0
213 1 0 216 1 0 220 1 0 227 1 0
230 1 0 234 1 0 246 1 0 265 1 0
304 1 0 216 0 0 244 0 0 142 1 1
156 1 1 163 1 1 198 1 1 205 1 1
232 1 1 232 1 1 233 1 1 233 1 1
233 1 1 233 1 1 239 1 1 240 1 1
261 1 1 280 1 1 280 1 1 296 1 1
296 1 1 323 1 1 204 0 1 344 0 1
;
data _oracle_input; set Rats; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc phreg data=_oracle_input;
by _oracle_by;
model Days*Status(0)=Group;
run;
