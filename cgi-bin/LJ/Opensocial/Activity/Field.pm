# LJ/Opensocial/Activity/Field.pm - jop

package LJ::Opensocial::Activity::Field;
use LJ::Opensocial::Util::FieldBase;
our @ISA = ( LJ::Opensocial::Util::FieldBase );
*AUTOLOAD = \&LJ::Opensocial::Util::FieldBase::AUTOLOAD;

our @m_fields = qw( APP_ID
                    BODY
                    BODY_ID
                    EXTERNAL_ID
                    ID
                    MEDIA_ITEMS
                    POSTED_TIME
                    PRIORITY
                    STREAM_FAVICON_URL
                    STREAM_SOURCE_URL
                    STREAM_TITLE
                    STREAM_URL
                    TEMPLATE_PARAMS
                    TITLE
                    TITLE_ID
                    URL
                    USER_ID
                  );

#####

1;

# End of file.
