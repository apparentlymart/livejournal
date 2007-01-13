package LJ::Directory::MajorRegion;
use strict;
use warnings;

# helper functions for location canonicalization and equivalance, etc.

my @reg = @LJ::MAJ_REGION_LIST;
if (!@reg || $LJ::_T_DEFAULT_MAJREGIONS) {
    @reg = (
                [1, "US"],
                [2, 'US-AA', part_of => 'US'],
                [3, 'US-AE', part_of => 'US'],
                [4, 'US-AK', part_of => 'US'],
                [5, 'US-AL', part_of => 'US'],
                [6, 'US-AP', part_of => 'US'],
                [7, 'US-AR', part_of => 'US'],
                [8, 'US-AS', part_of => 'US'],
                [9, 'US-AZ', part_of => 'US'],
                [10, 'US-CA', part_of => 'US'],
                [11, 'US-CO', part_of => 'US'],
                [12, 'US-CT', part_of => 'US'],
                [13, 'US-DC', part_of => 'US'],
                [14, 'US-DE', part_of => 'US'],
                [15, 'US-FL', part_of => 'US'],
                [16, 'US-FM', part_of => 'US'],
                [17, 'US-GA', part_of => 'US'],
                [18, 'US-GU', part_of => 'US'],
                [19, 'US-HI', part_of => 'US'],
                [20, 'US-IA', part_of => 'US'],
                [21, 'US-ID', part_of => 'US'],
                [22, 'US-IL', part_of => 'US'],
                [23, 'US-IN', part_of => 'US'],
                [24, 'US-KS', part_of => 'US'],
                [25, 'US-KY', part_of => 'US'],
                [26, 'US-LA', part_of => 'US'],
                [27, 'US-MA', part_of => 'US'],
                [28, 'US-MD', part_of => 'US'],
                [29, 'US-ME', part_of => 'US'],
                [30, 'US-MH', part_of => 'US'],
                [31, 'US-MI', part_of => 'US'],
                [32, 'US-MN', part_of => 'US'],
                [33, 'US-MO', part_of => 'US'],
                [34, 'US-MP', part_of => 'US'],
                [35, 'US-MS', part_of => 'US'],
                [36, 'US-MT', part_of => 'US'],
                [37, 'US-NC', part_of => 'US'],
                [38, 'US-ND', part_of => 'US'],
                [39, 'US-NE', part_of => 'US'],
                [40, 'US-NH', part_of => 'US'],
                [41, 'US-NJ', part_of => 'US'],
                [42, 'US-NM', part_of => 'US'],
                [43, 'US-NV', part_of => 'US'],
                [44, 'US-NY', part_of => 'US'],
                [45, 'US-OH', part_of => 'US'],
                [46, 'US-OK', part_of => 'US'],
                [47, 'US-OR', part_of => 'US'],
                [48, 'US-PA', part_of => 'US'],
                [49, 'US-PR', part_of => 'US'],
                [50, 'US-RI', part_of => 'US'],
                [51, 'US-SC', part_of => 'US'],
                [52, 'US-SD', part_of => 'US'],
                [53, 'US-TN', part_of => 'US'],
                [54, 'US-TX', part_of => 'US'],
                [55, 'US-UT', part_of => 'US'],
                [56, 'US-VA', part_of => 'US'],
                [57, 'US-VI', part_of => 'US'],
                [58, 'US-VT', part_of => 'US'],
                [59, 'US-WA', part_of => 'US'],
                [60, 'US-WI', part_of => 'US'],
                [61, 'US-WV', part_of => 'US'],
                [62, 'US-WY', part_of => 'US'],

                [63, 'RU'],
                [64, 'RU-Moscow',  part_of => 'RU',
                 spelled => [
                             qr/^RU-.*-Mos[ck]ow/i, # english
                             # cyrillic. ignore state. capital or lowercase M.
                             qr/^RU-.*-\xd0[\x9c\xbc]\xd0\xbe\xd1\x81\xd0\xba\xd0\xb2\xd0\xb0/,
                             qr/^RU-.*-(Mo[sc]kau|Moskva|Msk)/i,
                             ],
                 ],
                [65, 'RU-StPetersburg', part_of => 'RU',
                 spelled => [
                             # Sankt-Peterburg:
                             qr/^RU-.*-\xd0\xa1\xd0\xb0\xd0\xbd\xd0\xba\xd1\x82-\xd0\x9f\xd0\xb5\xd1\x82\xd0\xb5\xd1\x80\xd0\xb1\xd1\x83\xd1\x80\xd0\xb3/,
                             # Piter:
                             qr/^RU-.*-\xd0\x9f\xd0\xb8\xd1\x82\xd0\xb5\xd1\x80/,
                             qr/^RU-.*-P[ie]ter/,
                             # English variations:
                             qr/^RU-.*-((Saint|St|Sankt|S)[\. \-]{0,2})?P[ei]ters?b(u|i|e|ou)rg/i,
                             # SPB:
                             qr/^RU-.*-\xd0\xa1\xd0\x9f\xd0\xb1/,
                             qr/^RU-.*-SPB/i,
                             # Peterburg:
                             qr/^RU-.*-\xd0\x9f\xd0\xb5\xd1\x82\xd0\xb5\xd1\x80\xd0\xb1\xd1\x83\xd1\x80\xd0\xb3/,
                             ]],

                [66, "CA"],
                [67, "UK"],
                [68, "AU"],
            );
}

my %code2reg;  # "US" => LJ::Directory::MajorRegion object
my %id2reg;    # id   => LJ::Directory::MajorRegion object

build_reg_objs();
sub build_reg_objs {
    my $n = 0;
    foreach my $reg (@reg) {
        my ($id, $code, %args) = @$reg;
        die "Duplicate ID $id"     if $id2reg{$id};
        die "Duplicate code $code" if $code2reg{$code};
        $id2reg{$id} = $code2reg{$code} = LJ::Directory::MajorRegion->new(id          => $id,
                                                                          code        => $code,
                                                                          parent_code => $args{part_of},
                                                                          spelled     => $args{spelled});
    }
}

# --------------------------------------------------------------------------
# Instance methods

sub id { $_[0]{id} }
sub code { $_[0]{code} }

sub has_ancestor_id {
    my ($reg, $ancid) = @_;
    my $iter = $reg;
    while ($iter->{parent_code} && ($iter = $code2reg{$iter->{parent_code}})) {
        return 1 if $iter->id == $ancid;
    }
    return 0;
}

# --------------------------------------------------------------------------
# Package methods


sub new {
    my ($pkg, %args) = @_;
    return bless \%args, $pkg;
}


# returns list of region ids from a search request ($countrycode,
# $statecode||$state, $city) that are part of that region.  returns
# empty list if unrecognized.
sub region_ids {
    my ($pkg, $country, $state, $city) = @_;
    my $regid = $pkg->region_id($country, $state, $city)
        or return ();
    return ($regid, $pkg->subregion_ids($regid));
}

sub subregion_ids {
    my ($pkgid, $rootid) = @_;
    my @ret;
    foreach my $reg (values %code2reg) {
        push @ret, $reg->id if $reg->has_ancestor_id($rootid);
    }
    return @ret;
}

sub region_id {
    my ($pkg, $country, $state, $city) = @_;
    $country ||= "";
    $state   ||= "";
    $city    ||= "";
    my $locstr = join("-", $country, $state, $city);

    foreach my $reg (values %code2reg) {
        if (my $splist = $reg->{spelled}) {
            foreach my $spi (@$splist) {
                return $reg->id if
                    (ref $spi && $locstr =~ /$spi/) ||
                    $locstr eq $spi;
            }
        } else {
            return $reg->id if !$city && $reg->code eq "$country-$state";
            return $reg->id if !$city && !$state && $reg->code eq "$country";
        }
    }

    return;
}

sub most_specific_matching_region_id {
    my ($pkg, $country, $state, $city) = @_;
    return
        $pkg->region_id($country, $state, $city) ||
        $pkg->region_id($country, $state) ||
        $pkg->region_id($country);
}

1;
