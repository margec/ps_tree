#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

=pod

input: ps -e l
output: ps -eo pid,command --forest

$ ./ps_tree.pl
  - if run with no argument, this script will get a snapshot of 'ps -e l', save it to a file 'ps_in' (in the same directory) for ease of checking the result

$ ./ps_tree.pl <file>
  - if run with a file name argument, this script will read the ps snapshot from the specified file (in the same directory)

=cut

my $FORMAT = "%*s  %s%s\n";
my $PID_COL_WIDTH = 5;

&main();
exit 0;

sub main {

    # get ps input
    if (scalar(@ARGV) > 1) {
        print "Usage: ./ps_tree.pl [<file>]\n";
        return;
    }
    my (@ps_lines, $fh, $file);
    if (scalar(@ARGV) == 0) { # call real time
        open($fh, '-|', 'ps -e l') or die "can't fork(): $!";
        @ps_lines = <$fh>;
        close($fh);
        $file = 'ps_in';
        open($fh, '>', "./$file") or die "can't open '$file': $!"; # write the snapshot to a file for checking
        print $fh @ps_lines;
        close($fh);

        open($fh, '-|', 'ps -eo pid,command --forest') or die "can't fork(): $!";
        my @ps_lines1 = <$fh>;
        close($fh);
        $file = 'ps_out1';
        open($fh, '>', "./$file") or die "can't open '$file': $!"; # write the snapshot to a file for checking
        print $fh @ps_lines1;
        close($fh);

    } elsif (scalar(@ARGV) == 1) { # use file
        $file = "./$ARGV[0]";
        open($fh, $file) or die "can't open '$file': $!";
        @ps_lines = <$fh>;
        close($fh);
    }

    # build subtrees
    my %subtrees = ();
    my ($node, $index, $seen_pids, $seen_ppids);
    foreach my $ps_line (@ps_lines) {
        chomp($ps_line);
        $ps_line =~ s/^\s+//;
        my @cols = split(/\s+/, $ps_line);
        if ($ps_line =~ /^\D/) { # find position of columns
            for (my $i=0; $i<=$#cols; $i++) {
                if ($cols[$i] =~ /(PPID|PID|COMMAND|CMD)/) {
                    $index->{$1} = $i;
                }
            }
            next;
        }
        my $pid = $cols[$index->{'PID'}];
        my $ppid = $cols[$index->{'PPID'}];
        my $cmd_index = $index->{'COMMAND'} || $index->{'CMD'};
        my @cmd_parts = ();
        for (my $i=$cmd_index; $i<=$#cols; $i++) {
            push(@cmd_parts, $cols[$i]);
        }
        my $cmd = join(' ', @cmd_parts);
        my $node = { pid => $pid, cmd => $cmd, ppid => $ppid, child => undef, sibling => undef };
        # insert node
        if ((!$seen_pids->{$ppid} && !$seen_ppids->{$ppid}) || ($pid <= 2)) { # if we haven't seen the node's parent, create a new subtree
            $subtrees{$pid} = $node;
            $seen_pids->{$pid} = 1;
            $seen_ppids->{$ppid} = 1;
            next;
        }
        foreach my $id (keys %subtrees) {
            if (&insert_node($subtrees{$id}, $node)) {
                last;
            }
        }
        $seen_pids->{$pid} = 1;
        $seen_ppids->{$ppid} = 1;
    }
    #print "after insert tree ", Dumper(\%subtrees), "\n"; # debug

    # merge subtrees
    if (scalar(keys %subtrees) > 2) {
        &merge_subtrees(\%subtrees);
        #print "after merge subtrees ", Dumper(\%subtrees), "\n"; # debug
    }

    # traverse subtrees (pre-order)
    printf($FORMAT, $PID_COL_WIDTH, 'PID', '', 'COMMAND');
    foreach my $id (sort { $b <=> $a } keys %subtrees) {
        next if $id>2;
        &traverse_tree($subtrees{$id}, $id-2);
    }
}

sub insert_node {
    my ($tree, $node) = @_;

    if ($node->{ppid} == $tree->{pid}) { # insert node as a child to tree
        if (my $child = $tree->{child}) { # go to the end
            while ($child->{sibling}) {
                $child = $child->{sibling};
            }
            $child->{sibling} = $node;
        } else {
            $tree->{child} = $node;
        }
        #$node->{sibling} = $tree->{child}; # put in front
        #$tree->{child} = $node;
        return 1;
    }

    if ($node->{ppid} == $tree->{ppid}) { # insert node as a sibling to tree
        if (my $sibling = $tree->{sibling}) { # go to the end
            while ($sibling->{sibling}) {
                $sibling = $sibling->{sibling};
            }
            $sibling->{sibling} = $node;
        } else {
            $tree->{sibling} = $node;
        }
        #$node->{sibling} = $tree->{sibling}; # put in front
        #$tree->{sibling} = $node;
        return 1;
    }

    if ($tree->{child}) {
        if (&insert_node($tree->{child}, $node)) { # follow the tree's child
            return 1;
        }
    }

    if ($tree->{sibling}) {
        if (&insert_node($tree->{sibling}, $node)) { # follow the tree's sibling
            return 1;
        }
    }

    return 0;
}

sub merge_subtrees {
    my $subtrees = shift;

    foreach my $id (keys %$subtrees) {
        next if $id < 3;
        foreach my $goid (keys %$subtrees) {
            next if $goid > 2;
            if (&insert_node($subtrees->{$goid}, $subtrees->{$id})) {
                last;
            }
        }
    }
}

sub traverse_tree {
    my $tree = shift;
    my $depth = shift;
    my $show_connect_bar = shift;

    my $indent = '';
    my $has_shown = 0;
    if ($depth > 0) {
        for(my $i=1; $i<$depth; $i++) {
            if ($show_connect_bar && !$has_shown) {
                $indent .= " \|  ";
                $has_shown = 1;
            } else {
                $indent .= "    ";
            }
        }
        $indent .= " \\_ ";
    }

    printf($FORMAT, $PID_COL_WIDTH, $tree->{pid}, $indent, $tree->{cmd}); # visit self

    if ($tree->{child}) { # if child exists, visit child
        if (!defined($show_connect_bar)) {
            $show_connect_bar = 1 if $depth >= 1 && $tree->{sibling};
        }
        &traverse_tree($tree->{child}, $depth+1, $show_connect_bar); 
    }

    if ($tree->{sibling}) { # if sibling exists, visit sibling
        &traverse_tree($tree->{sibling}, $depth); 
    }
}
