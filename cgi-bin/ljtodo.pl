#!/usr/bin/perl
#

package LJ::Todo;

sub get_permissions
{
    my ($dbh, $perm, $opts) = @_;
    my $sth;
    my $u = $opts->{'user'};
    my $remote = $opts->{'remote'};
    my $it = $opts->{'item'};

    return () unless $remote;

    if ($u->{'userid'} == $remote->{'userid'}) {
        $perm->{'delete'} = 1;
        $perm->{'edit'} = 1;
        $perm->{'add'} = 1;
    } else {
        my $quser = $dbh->quote($u->{'user'});
        
        ## check if you're an admin of that journal 
        my $is_manager = LJ::check_rel($u, $remote, 'A');
        if ($is_manager) {
            $perm->{'add'} = 1;
            $perm->{'delete'} = 1;
            $perm->{'edit'} = 1;
        } else {
            $sth = $dbh->prepare("SELECT fg.groupname FROM friends f, friendgroup fg WHERE f.userid=$u->{'userid'} and f.friendid=$remote->{'userid'} and fg.userid=$u->{'userid'} and fg.groupname like 'priv-todo-%'");
            $sth->execute;
            while (my ($priv) = $sth->fetchrow_array) {
                if ($priv =~ /^priv-todo-(.+)/) {
                    $perm->{$1} = 1;
                }
            }
            ## check to see if user allows it
            
        }
    }
        
    return %permission;
}


1;
