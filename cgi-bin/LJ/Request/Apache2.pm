package LJ::Request::Apache2;
use strict;

use Apache2::Const;
use Apache2::RequestRec;
use Apache2::Response;
use Apache2::RequestIO;
use Apache2::Request;
use Apache2::ServerUtil;
use Apache2::Log;
use Apache2::Access;
use Apache2::Connection;
use Apache2::URI;
use ModPerl::Util;


sub LJ::Request::OK                        { return Apache2::Const::OK() }
sub LJ::Request::REDIRECT                  { return Apache2::Const::REDIRECT() }
sub LJ::Request::DECLINED                  { return Apache2::Const::DECLINED() }
sub LJ::Request::FORBIDDEN                 { return Apache2::Const::FORBIDDEN() }
sub LJ::Request::NOT_FOUND                 { return Apache2::Const::NOT_FOUND() }
sub LJ::Request::HTTP_NOT_MODIFIED         { return Apache2::Const::HTTP_NOT_MODIFIED() }
sub LJ::Request::HTTP_MOVED_PERMANENTLY    { return Apache2::Const::HTTP_MOVED_PERMANENTLY() }
sub LJ::Request::HTTP_MOVED_TEMPORARILY    { return Apache2::Const::HTTP_MOVED_TEMPORARILY() }
sub LJ::Request::M_TRACE                   { return Apache2::Const::M_TRACE() }
sub LJ::Request::M_OPTIONS                 { return Apache2::Const::M_OPTIONS() }
sub LJ::Request::SERVER_ERROR              { return Apache2::Const::SERVER_ERROR() }
sub LJ::Request::BAD_REQUEST               { return Apache2::Const::BAD_REQUEST() }


my $instance = '';
sub LJ::Request::request { $instance }
sub LJ::Request::r {
    die "Request is not provided to LJ::Request" unless $instance;
    return $instance->{r};
}


sub LJ::Request::instance {
    my $class = shift;
    die "use 'request' instead";
}


sub LJ::Request::init {
    my $class = shift;
    my $r     = shift;

    $instance = bless {}, $class;
    $instance->{apr} = Apache2::Request->new($r);
    $instance->{r} = $r;
    return $instance;
}

sub LJ::Request::is_inited {
    return $instance ? 1 : 0;
}

sub LJ::Request::update_mtime {
    my $class = shift;
    die "Request is not provided to LJ::Request" unless $instance;
    return $instance->{r}->update_mtime(@_);
}

sub LJ::Request::set_last_modified {
    my $class = shift;
    die "Request is not provided to LJ::Request" unless $instance;
    return $instance->{r}->set_last_modified(@_);
}

sub LJ::Request::request_time {
    my $class = shift;
    die "Request is not provided to LJ::Request" unless $instance;
    return $instance->{r}->request_time();
}

sub LJ::Request::read {
    my $class = shift;
    die "Request is not provided to LJ::Request" unless $instance;
    return $instance->{r}->read(@_);
}

sub LJ::Request::is_main {
    my $class = shift;
    die "Request is not provided to LJ::Request" unless $instance;
    return !$instance->{r}->main;
}

sub LJ::Request::main {
    my $class = shift;
    die "Request is not provided to LJ::Request" unless $instance;
    return $instance->{r}->main(@_);
}

sub LJ::Request::dir_config {
    my $class = shift;
    die "Request is not provided to LJ::Request" unless $instance;
    return $instance->{r}->dir_config(@_);
}

sub LJ::Request::header_only {
    my $class = shift;
    die "Request is not provided to LJ::Request" unless $instance;
    return $instance->{r}->header_only;
}

sub LJ::Request::content_languages {
    my $class = shift;
    die "Request is not provided to LJ::Request" unless $instance;
    return $instance->{r}->content_languages(@_);
}

sub LJ::Request::register_cleanup {
    my $class = shift;
    return $instance->{r}->pool->cleanup_register(@_);
}

sub LJ::Request::path_info {
    my $class = shift;
    return $instance->{r}->path_info(@_);
}

sub LJ::Request::args {
    my $class = shift;
    return $instance->{r}->args(@_);
}

sub LJ::Request::method {
    my $class = shift;
    $instance->{r}->method;
}

sub LJ::Request::bytes_sent {
    my $class = shift;
    $instance->{r}->bytes_sent(@_);
}

sub LJ::Request::document_root {
    my $class = shift;
    $instance->{r}->document_root;
}

sub LJ::Request::finfo {
    my $class = shift;
    $instance->{r}->finfo;
}

sub LJ::Request::filename {
    my $class = shift;
    $instance->{r}->filename(@_);
}

sub LJ::Request::add_httpd_conf {
    my $class = shift;
    Apache2::ServerUtil->server->add_config(@_);
}

sub LJ::Request::is_initial_req {
    my $class = shift;
    $instance->{r}->is_initial_req(@_);
}

sub LJ::Request::push_handlers_global {
    my $class = shift;
    Apache2::ServerUtil->server->push_handlers(@_);
}

sub LJ::Request::push_handlers {
    my $class = shift;
    return $instance->{r}->push_handlers(@_);
}

sub LJ::Request::set_handlers {
    my $class = shift;
    $instance->{r}->set_handlers(@_);
}

sub LJ::Request::handler {
    my $class = shift;
    $instance->{r}->handler(@_);
}

sub LJ::Request::method_number {
    my $class = shift;
    return $instance->{r}->method_number(@_);
}

sub LJ::Request::status {
    my $class = shift;
    return $instance->{r}->status(@_);
}

sub LJ::Request::status_line {
    my $class = shift;
    return $instance->{r}->status_line(@_);
}

##
##
##
sub LJ::Request::free {
    my $class = shift;
    $instance = undef;
}

# use pnotes instead of notes
sub LJ::Request::notes {
    my $class = shift;
    $instance->{apr}->pnotes (@_);
}

sub LJ::Request::pnotes {
    my $class = shift;
    $instance->{apr}->pnotes (@_);
}

sub LJ::Request::parse {
    my $class = shift;
    $instance->{apr}->parse (@_);
}

sub LJ::Request::uri {
    my $class = shift;
    $instance->{apr}->uri (@_);
}

sub LJ::Request::hostname {
    my $class = shift;
    $instance->{apr}->hostname (@_);
}

sub LJ::Request::header_out {
    my $class = shift;
    my $header = shift;
    if (@_ > 0){
        return $instance->{r}->err_headers_out->{$header} = shift;
    } else {
        return $instance->{r}->err_headers_out->{$header};
    }
}

sub LJ::Request::headers_out {
    my $class = shift;
    $instance->{apr}->headers_out (@_);
}

sub LJ::Request::header_in {
    my $class = shift;
    my $header = shift;
    if (@_ > 0){
        return $instance->{r}->headers_in->{$header} = shift;
    } else {
        return $instance->{r}->headers_in->{$header};
    }
}

sub LJ::Request::headers_in {
    my $class = shift;
    $instance->{r}->headers_in();
}

sub LJ::Request::param {
    my $class = shift;
    $instance->{apr}->param (@_);
}

sub LJ::Request::no_cache {
    my $class = shift;
    $instance->{r}->no_cache (@_);
}

sub LJ::Request::content_type {
    my $class = shift;
    $instance->{r}->content_type (@_);
}

sub LJ::Request::pool {
    my $class = shift;
    $instance->{r}->pool;
}

sub LJ::Request::connection {
    my $class = shift;
    $instance->{r}->connection;
}

sub LJ::Request::output_filters {
    my $class = shift;
    $instance->{r}->output_filters(@_);
}

sub LJ::Request::print {
    my $class = shift;
    $instance->{r}->print (@_);
}

sub LJ::Request::content_encoding {
    my $class = shift;
    $instance->{r}->content_encoding(@_);
}

sub LJ::Request::send_http_header {
    my $class = shift;
    # http://perl.apache.org/docs/2.0/user/porting/compat.html#C____r_E_gt_send_http_header___
    # This method is not needed in 2.0,
    1
}


sub LJ::Request::err_headers_out {
    my $class = shift;
    $instance->{apr}->err_headers_out (@_)
}



## Returns Array (Key, Value, Key, Value) which can be converted to HASH.
## But there can be some params with the same name!
#
# TODO: do we need this and 'args' methods? they are much the same.
sub LJ::Request::get_params {
    my $class = shift;
    if (wantarray) {
        my @params = $instance->{r}->args;
        return @params;
    } else {
        my $query_string = $instance->{r}->args;
        return $query_string;
    }
}
sub LJ::Request::post_params {
    my $class = shift;

    return @{ $instance->{params} } if $instance->{params};
    my @params = $instance->{apr}->body;
    $instance->{params} = \@params;
    return @params;

}


sub LJ::Request::add_header_out {
    my $class  = shift;
    my $header = shift;
    my $value  = shift;

    $instance->{r}->err_headers_out->add($header, $value);
    $instance->{r}->headers_out->add($header, $value);

    return 1;
}

# TODO: maybe remove next method and use 'header_out' instead?
sub LJ::Request::set_header_out {
    my $class  = shift;
    my $header = shift;
    my $value  = shift;

    $instance->{r}->err_header_out->set($header, $value);
    $instance->{r}->headers_out->set($header, $value);

    return 1;
}

sub LJ::Request::unset_headers_in {
    my $class = shift;
    my $header = shift;
    $instance->{r}->headers_in->unset($header);
}

sub LJ::Request::log_error {
    my $class = shift;
    return $instance->{r}->log_error(@_);
}

sub LJ::Request::remote_ip {
    my $class = shift;
    return $instance->{r}->connection()->remote_ip(@_);
}

sub LJ::Request::remote_host {
    my $class = shift;
    return $instance->{r}->connection()->remote_host;
}

sub LJ::Request::user {
    my $class = shift;
    return $instance->{r}->auth_name();
}

sub LJ::Request::aborted {
    my $class = shift;
    return $instance->{r}->connection()->aborted;
}


sub LJ::Request::sendfile {
    my $class = shift;
    my $filename = shift;
    my $fh       = shift; # used in Apache v.1

    return $instance->{r}->sendfile($filename);
}

sub LJ::Request::parsed_uri {
    my $class = shift;
    $instance->{r}->parsed_uri; # Apache2::URI
}

sub LJ::Request::current_callback {
    my $class = shift;
    return ModPerl::Util::current_callback();
}

sub LJ::Request::child_terminate {
    my $class = shift;
    return $instance->{r}->child_terminate;
}


1;
