=head1 NAME

LJ::Identity - a module for handling external identities (like OpenID)
in LiveJournal

=head1 SYNOPSIS

 # load or create an identity account
 my $u = LJ::User::load_identity_user(
    'O', # OpenID
    $openid_url,
    { 'vident' => $vident }, # OpenID-specific "verified identity" data
 );
 warn $u; # 'LJ::User=HASH(0xDEADBEEF)'
 
 # manipulate the account in an identity-specific way
 my $id = $u->identity;
 warn $id->pretty_type; # 'OpenID'
 
 # redirect the remote user to a third-party site for verification,
 # requesting that once they log in, they return to the specified site
 # page; note that the identity may wish to see some specific form
 # submission with the data to process
 LJ::Identity::OpenID->attempt_login(
    \@errors, # caller-allocated list for storing error messages for the
              # user. if undefined, the errors are silently discarded

    # return to this page on success:
    'returl' => $LJ::SITEROOT,

    # and to this page in case of a failure:
    'returl_fail' => $LJ::SITEROOT,
 );

=cut

package LJ::Identity;
use strict;

use Carp qw();
use URI qw();

# initialization code. do not touch this.
my @CLASSES = LJ::ModuleLoader->module_subclasses('LJ::Identity');
foreach my $class (@CLASSES) {
    eval "use $class";
    Carp::confess "Error loading event module '$class': $@" if $@;
}

my %TYPEMAP = map { $_->typeid => $_ } @CLASSES;
my %TYPEMAP_SHORT_CODES = map { $_->short_code => $_ } @CLASSES;

# initialization code ends

=head1 DEFINED METHODS

=head2 Parent class functions; final

=over 2

=item *

find_class: find a class with the specified short code; see also the
short_code function.

 warn LJ::Identity->find_class('openid'); # 'LJ::Identity::OpenID'

=item *

new: a constructor, constructing an identity object with the proper
class matching the passed 'typeid' and 'value' params.

 warn LJ::Identity->new('typeid' => 'O', 'value' => $url);
 # 'LJ::Identity::OpenID=HASH(0xDEADBEEF)'

You probably should use $u->identity instead, which calls this function.

=back

=cut

sub find_class {
    my ($class, $short_code) = @_;
    return $TYPEMAP_SHORT_CODES{$short_code};
}

sub new {
    my ($class, %opts) = @_;

    if ( my $subclass = $TYPEMAP{ $opts{'typeid'} } ) {
        return bless {
            'value' => $opts{'value'},
        }, $subclass;
    } else {
        return bless {
            'value' => $opts{'value'},
            'typeid' => $opts{'typeid'},
        }, $class;
    }
}

=head2 Getter(s)

=over 2

=item *

value: returns the identity-specific identifier for the user, such as
a URL used for OpenID identification.

=back

=cut

sub value {
    my ($self) = @_;
    return $self->{'value'};
}

=head2 (Purely) virtual functions, thousands of them

=over 2

=item *

pretty_type: return a "fancy" identity type description that can be
displayed to a user. Used by ljprotocol.pl in the 'list_friends' method.

 warn $u->identity->pretty_type; # 'OpenID'

=item *

typeid: a one character long string containing a code that represents
this identity type in the database. Used by the constructor indirectly.

 warn $u->identity->short_code; # 'O'

=item *

short_code: a string containing a "readable" code specific for the
identity type. There are two intended uses: elsewhere in the code
it is more readable to check C<$id->short_code eq 'openid'> than to check
C<$id->typeid eq 'O'>; also, it should be used as a value to a form field
specifying the identity type, so that the form handler can call find_class
to find the identity class.

=item *

url: return an identity-specific URL to be used for the "website" field
in the user's profile. Used by sub LJ::User::url.

=item *

attempt_login: verify the remote user's identity, redirecting to a
specified page afterwards. See the example in the SYNOPSIS part.
Used by htdocs/identity/login.bml.

=item *

initialize_user: initialize the user's profile by the data provided
by the identity provider. Used by sub LJ::User::load_identity_user the
first time the user with a particular identity logs in to the site.

=item *

display_name: return a publicly-displayed name of the user. Used by
sub LJ::User::display_name.

=item *

ljuser_display_params: return a hashref containing some params
for the E<lt>lj user="username"E<gt> tag display; the params interpreted
are 'profile_url', 'journal_url, 'journal_name', 'userhead','userhead_w',
and 'userhead_h'. Used by sub LJ::ljuser in cgi-bin/LJ/User.pm. Please
refer to the source code of this function for details.

=item *

profile_window_title: return a string to be used as a window title
for the profile page of this user. Used in htdocs/userinfo.bml. It is
suggested that implementations use LJ::Lang::ml for i18n.

=item *

enabled: return a boolean value indicating that this identity type is
enabled on the server. Disabled identity types are not displayed to the
user.

=back

=cut

sub pretty_type             { 'unknown' }
sub typeid                  { my ($self) = @_; return $self->{'typeid'} }
sub short_code              { 'U' }
sub url                     { my ( $self, $u ) = @_; return $u->journal_base; }
sub attempt_login           { Carp::confess 'Invalid identity type' }
sub initialize_user         { Carp::confess 'Invalid identity type' }
sub display_name            { my ( $self, $u ) = @_; return $u->username; }
sub ljuser_display_params   { return {}; }
sub profile_window_title    { return LJ::Lang::ml('/userinfo.bml.title'); }

sub enabled { 1 }

sub unpack_forwhat {
    my ($class, $forwhat) = @_;

    my ($returl, $returl_fail);
    if ($forwhat eq 'login') {
        $returl = $LJ::SITEROOT;
        $returl_fail = "$LJ::SITEROOT/identity/login.bml?type=" . $class->short_code;
    } elsif ($forwhat =~ /^comment-(\d+)-(\d+)$/) {
        my ($journalid, $pendcid) = ($1, $2);

        $returl = "$LJ::SITEROOT/talkpost_do.bml?" .
                  "jid=$journalid&" .
                  "pendcid=$pendcid";
        $returl_fail = $returl . '&failed=1';
    } elsif ($forwhat eq 'external') {
        $returl      = "$LJ::SITEROOT/gadgets/external-landing.bml?success";
        $returl_fail = "$LJ::SITEROOT/gadgets/external-landing.bml?fail";
    } elsif ( $forwhat =~ /^journal\-([a-z_]+)(?:-(.*))?$/i ) {
        my ( $journal, $extra ) = ( $1, $2 );
        my $journalu = LJ::load_user($journal);

        unless ($journalu) {
            warn 'invalid journal';
            die;
        }

        if ( !$extra ) {
            # the journal itself
            $returl = $returl_fail = $journalu->journal_base;
        } elsif ( $extra =~ /^\d+$/ ) {
            # an entry in the journal

            my $entry = LJ::Entry->new( $journalu, 'ditemid' => $extra );

            unless ($entry) {
                warn 'invalid entry';
                die;
            }

            $returl = $returl_fail = $entry->url;
        } elsif ( $extra =~ /^tags-(or|and)-([\d\-]+)$/ ) {
            my ( $mode, $tagspec ) = ( $1, $2 );

            my @tagids = split /-/, $tagspec;

            my $tags = LJ::Tags::get_usertags($journalu);
            my @tagnames = map { LJ::eurl( $tags->{$_}->{'name'} ) } @tagids;

            $returl = $journalu->journal_base . '/tag/'
                    . join( ',', @tagnames )
                    . '?mode=' . $mode;

            $returl_fail = $returl;
        } else {
            warn 'invalid format ' . $extra;
            die;
        }
    } elsif ( $forwhat =~ /^oauth\-([a-z0-9]+)$/i ) {
        $returl = "$LJ::SSLROOT/oauth/authorize_token.bml?oauth_token=$1";
        $returl_fail = $returl;
    } else {
        # the warning will sit in error logs, and the exception
        # will be handled
        warn "invalid forwhat passed: $forwhat";
        die;
    }

    return ($returl, $returl_fail);
}

1;
