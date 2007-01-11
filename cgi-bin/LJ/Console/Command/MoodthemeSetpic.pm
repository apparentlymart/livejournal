package LJ::Console::Command::MoodthemeSetpic;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "moodtheme_setpic" }

sub desc { "Change data for a mood theme. If picurl, width, or height is empty or zero, the data is deleted." }

sub args_desc { [
                 'themeid' => "Mood theme ID number.",
                 'moodid' => "Mood ID number.",
                 'picurl' => "URL of picture for this mood. Use /img/mood/themename/file.gif for public mood images",
                 'width' => "Width of picture",
                 'height' => "Height of picture",
                 ] }

sub usage { '<themeid> <moodid> <picurl> <width> <height>' }

sub can_execute { 1 }

sub execute {
    my ($self, $themeid, $moodid, $picurl, $width, $height, @args) = @_;

    return $self->error("This command takes five arguments. Consult the reference.")
        unless scalar(@args) == 0;

    my $remote = LJ::get_remote();
    return $self->error("Sorry, your account type doesn't let you create new mood themes")
        unless $remote->get_cap("moodthemecreate");

    my $dbh = LJ::get_db_writer();

    my $sth = $dbh->prepare("SELECT ownerid FROM moodthemes WHERE moodthemeid = ?", undef, $themeid);
    $sth->execute;
    my $owner = $sth->fetchrow_array;
    return $self->error("You do not own this mood theme.")
        unless $owner = $remote->id;

    $width += 0;
    $height += 0;
    $moodid += 0;

    if (!$picurl || $width == 0 || $height == 0) {
        $dbh->do("DELETE FROM moodthemedata WHERE moodthemeid = ? AND moodid= ?", undef, $themeid, $moodid);
        LJ::MemCache::delete([$themeid, "moodthemedata:$themeid"]);
        return $self->print("Data deleted for theme #$themeid, mood #$moodid");
    }

    $dbh->do("REPLACE INTO moodthemedata (moodthemeid, moodid, picurl, width, height) VALUES (?, ?, ?, ?, ?)",
             undef, $themeid, $moodid, $picurl, $width, $height);
    LJ::MemCache::delete([$themeid, "moodthemedata:$themeid"]);
    $self->error("Database error: " . $dbh->errstr)
        if $dbh->err;

    return $self->print("Data inserted for theme #$themeid, mood #$moodid");
}

1;
