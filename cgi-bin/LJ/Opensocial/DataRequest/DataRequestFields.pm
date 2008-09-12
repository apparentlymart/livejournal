# LJ/Opensocial/DataRequest/DataRequestFields.pm - jop

package LJ::Opensocial::DataRequest::DataRequestFields;
use LJ::Opensocial::Util::FieldBase;
our @ISA = ( LJ::Opensocial::Util::FieldBase );
*AUTOLOAD = \&LJ::Opensocial::Util::FieldBase::AUTOLOAD;

our @m_fields = qw( 
                    ESCAPE_TYPE
                  );

#####

1;

# End of file.
