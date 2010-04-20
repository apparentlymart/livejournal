package LJ::Request::Text;
use strict;

my (
    $method,
    $get,
    $post,
    $cookie,
    $redirected,
);

sub LJ::Request::OK                        { 1 }
sub LJ::Request::REDIRECT                  { 2 }
sub LJ::Request::DECLINED                  { 3 }
sub LJ::Request::FORBIDDEN                 { 4 }
sub LJ::Request::HTTP_NOT_MODIFIED         { 5 }
sub LJ::Request::HTTP_MOVED_PERMANENTLY    { 6 }
sub LJ::Request::HTTP_MOVED_TEMPORARILY    { 7 }
sub LJ::Request::HTTP_METHOD_NOT_ALLOWED   { 8 }
sub LJ::Request::HTTP_BAD_REQUEST          { 9 }
sub LJ::Request::M_TRACE                   { 10 }
sub LJ::Request::M_OPTIONS                 { 11 }
sub LJ::Request::M_PUT                     { 12 }
sub LJ::Request::M_POST                    { 13 }
sub LJ::Request::NOT_FOUND                 { 14 }
sub LJ::Request::SERVER_ERROR              { 15 }
sub LJ::Request::BAD_REQUEST               { 16 }

sub init {
    my ($class, %params) = @_;

    $method = $params{'method'};
    $get = $params{'get'};
    $post = $params{'post'};
    $cookie = $params{'cookie'};
}

sub LJ::Request::method { $method }
sub LJ::Request::get_params { %$get }
sub LJ::Request::post_params { %$post }



1;
