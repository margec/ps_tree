# ps_tree

input: ps -e l
output: ps -eo pid,command --forest

$ ./ps_tree.pl
  - if run with no argument, this script will get a snapshot of 'ps -e l', save it to a file 'ps_in' (in the same directory) for ease of checking the result

$ ./ps_tree.pl <file>
  - if run with a file name argument, this script will read the ps snapshot from the specified file (in the same directory)
