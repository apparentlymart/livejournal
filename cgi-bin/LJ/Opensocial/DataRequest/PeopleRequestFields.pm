# LJ/Opensocial/DataRequest/PeopleRequestFields.pm - jop

package LJ::Opensocial::DataRequest::PeopleRequestFields;
use LJ::Opensocial::Util::FieldBase;
our @ISA = ( LJ::Opensocial::Util::FieldBase );
*AUTOLOAD = \&LJ::Opensocial::Util::FieldBase::AUTOLOAD;

use strict;

our @m_fields = qw { 
                     FILTER
                     FILTER_OPTIONS
                     FIRST
                     MAX
                     PROFILE_DETAILS
                     SORT_ORDER
                   };

#####

1;

# End of file.
