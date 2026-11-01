/* BUG-sasautosfilerefrebind: SASAUTOS keeps the fileref, not its old path. */
filename ac 'tests/autocall';
options sasautos=ac mautosource;
filename ac 'tests/autocall2';
%pick
