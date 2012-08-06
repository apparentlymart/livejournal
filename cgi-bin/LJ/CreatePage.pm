package LJ::CreatePage;
use strict;
use Carp qw(croak);

sub verify_username {
    my $class = shift;
    my $given_username = shift;
    my %opts = @_;

    my $post = $opts{post};
    my $second_submit_ref = $opts{second_submit_ref};
    my $error;

    $given_username = LJ::trim($given_username);
    
    unless ($given_username) {
        return $LJ::DISABLED{create_controller} ? LJ::Widget::CreateAccount->ml('widget.createaccount.error.username.mustenter') 
                                                : LJ::Widget::CreateAccount->ml('createaccount.error.username.mustenter');
    }
    if (length $given_username > 15) {
        return $LJ::DISABLED{create_controller} ? LJ::Lang::ml('error.usernamelong') 
                                                : LJ::Lang::ml('createaccount.error.usernamelong');
    }

    my $user = LJ::canonical_username($given_username);
    if (!$user) {
        return $LJ::DISABLED{create_controller} ? LJ::Lang::ml('error.usernameinvalid') 
                                                : LJ::Lang::ml('createaccount.error.usernameinvalid');
    }

    # you can give people sharedjournal priv ahead of time to create
    # reserved communities:
    if (! LJ::check_priv(LJ::get_remote(), "sharedjournal", $user)) {
        foreach my $re ("^system\$", @LJ::PROTECTED_USERNAMES) {
            if ($user =~ /$re/) {
                return $LJ::DISABLED{create_controller} ? LJ::Widget::CreateAccount->ml('widget.createaccount.error.username.reserved') 
                                                        : LJ::Widget::CreateAccount->ml('createaccount.error.username.reserved');
            }
        }
    }

    if (my $u = LJ::load_user($user)) {
        ##
        ## different rules for cases 
        ##  1) when we are going to create a new account with given username and
        ##  2) when we are going to rename into given username
        ##    
        if ($opts{'for_rename'}) {
            my $remote = LJ::get_remote();
            my $opts = {};
            if (! LJ::User::Rename::can_reuse_account($user, $remote, $opts)) {
                return $opts->{'error'} || "[Unknown error]";
            }
        } else {
            if ($u->is_expunged) {
                # do not create if this account name is purged
                return $LJ::DISABLED{create_controller} ? LJ::Widget::CreateAccount->ml(
                                                          'widget.createaccount.error.username.purged', 
                                                          { aopts => "href='$LJ::SITEROOT/rename/'" })
                                                        : LJ::Widget::CreateAccount->ml('createaccount.error.username.purged');
            } else {
                my $in_use = 1;
                # only do these checks on POST
                if ($post->{email} && $post->{password1}) {
                    if ($u->email_raw eq $post->{email}) {
                        if (LJ::login_ip_banned($u)) {
                            # brute-force possibly going on
                        } else {
                            if ($u->password eq $post->{password1}) {
                                # okay either they double-clicked the submit button
                                # or somebody entered an account name that already exists
                                # with the existing password
                                $$second_submit_ref = 1 if $second_submit_ref;
                                $in_use = 0;
                            } else {
                                LJ::handle_bad_login($u);
                            }
                        }
                    }
                }
                if ($in_use) {
                    return $LJ::DISABLED{create_controller} ? LJ::Widget::CreateAccount->ml( 'widget.createaccount.error.username.inuse') 
                                                            : LJ::Widget::CreateAccount->ml( 'createaccount.error.username.inuse');
                }
            }
        }
    }

    ## everything is ok
    return;
}

1;
