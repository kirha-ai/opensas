/* PERF-flownoteperrecord: a flowing LIST read must stay CORRECT while its
   Language Reference: Concepts p.171 "SAS went to a new line" NOTE becomes BOUNDED — capped at 20 per
   input stream plus one closing suppression NOTE (src/io.zig flowNote; the
   exact NOTE count is pinned by the in-file test "flow-over NOTE is capped per
   input stream" — NOTEs render to stderr, which this golden does not capture).
   45 one-token records = 22 flow events, 2 past the cap: the observations below
   pin that a capped log never disturbs the DATA — every obs keeps its own two
   values, no re-alignment.

   GAP-inputeofdegrade: there are TWENTY-TWO observations, not 23. Iteration 23
   reads a=45 from the last record and then needs a second token, so FLOWOVER goes
   looking for record 46 — Statements ref printed p.132, FLOWOVER "causes an INPUT
   statement to continue to read the next input data record" — and there is none,
   so printed p.178 applies: "If a DATA step tries to read another record after it
   reaches an end-of-file, then execution stops." The step ends at the INPUT and
   nothing is written for that iteration. It used to emit `n=23 a=45 b=.`, i.e.
   MISSOVER's documented "variables without any values assigned are set to
   missing" (printed p.133) applied while FLOWOVER was in effect. The reference
   prints this exact arithmetic for its own example at printed p.145 — three data
   lines, "the data set SCORES contains two, not three, observations". The 22
   surviving observations here are byte-identical, which is what this fixture is
   really guarding. */
data _null_;
  input a b;
  put 'n=' _n_ ' a=' a ' b=' b;
datalines;
1
2
3
4
5
6
7
8
9
10
11
12
13
14
15
16
17
18
19
20
21
22
23
24
25
26
27
28
29
30
31
32
33
34
35
36
37
38
39
40
41
42
43
44
45
;
run;
