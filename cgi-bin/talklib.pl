#!/usr/bin/perl
#
# Historical note:  the top of this code is damn old.
# I think Brad Whitaker wrote it for freevote.com in like '97 or something.
# It needs to die.

# Loads hash of icon info...
sub load_subjecticon
{
    $subjecticon_url = "$LJ::IMGPREFIX/talk";
    @subjecticon_types = (
    	"sm",
    	"md"
    );

    $subjecticon{'md'} = [
    	{ img => "md01_alien.gif",		w => 32,	h => 32 },
    	{ img => "md02_skull.gif",		w => 32,	h => 32 },
    	{ img => "md05_sick.gif",		w => 25,	h => 25 },
    	{ img => "md06_radioactive.gif",	w => 20,	h => 20 },
    	{ img => "md07_cool.gif",		w => 20,	h => 20 },
    	{ img => "md08_bulb.gif",		w => 17,	h => 23 },
    	{ img => "md09_thumbdown.gif",		w => 25,	h => 19 },
    	{ img => "md10_thumbup.gif",		w => 25,	h => 19 }
    ];
    $subjecticon{'sm'} = [
    	{ img => "sm01_smiley.gif",		w => 15,	h => 15 },
    	{ img => "sm02_wink.gif",		w => 15,	h => 15 },
    	{ img => "sm03_blush.gif",		w => 15,	h => 15 },
    	{ img => "sm04_shock.gif",		w => 15,	h => 15 },
    	{ img => "sm05_sad.gif",		w => 15,	h => 15 },
    	{ img => "sm06_angry.gif",		w => 15,	h => 15 },
    	{ img => "sm07_check.gif",		w => 15,	h => 15 },
    	{ img => "sm08_star.gif",		w => 20,	h => 18 },
    	{ img => "sm09_mail.gif",		w => 14,	h => 10 },
    	{ img => "sm10_eyes.gif",		w => 24,	h => 12 }
    ];

    # assemble ->{'id'} portion of hash.  the part of the imagename before the _
    foreach (keys %subjecticon) {
    	foreach (@{$subjecticon{$_}}) {
	   if ($_->{'img'} =~ /^(\D{2}\d{2})\_.+?$/) {
    	      $_->{'id'} = $1;
    	   }
    	}
    }
}

# Returns HTML to display an image, given the image id as an argument.
sub show_image
{
    my $id = shift;
    my $ico = "";

    return "" if ($id eq "none" || $id eq "");

    # make sure id is formatted properly and extract key it's under
    if ($id =~ /^(\D{2})\d{2}$/) {
       foreach (@{$subjecticon{$1}}) {
          if ($_->{'id'} eq $id) {
             return "<IMG SRC=\"$subjecticon_url/$_->{'img'}\" BORDER=0 WIDTH=$_->{'w'} HEIGHT=$_->{'h'} VALIGN=MIDDLE>";
          }
       }
    }
    return "";
}

package LJ::Talk;

1;
