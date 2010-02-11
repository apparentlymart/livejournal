package LJ::Request::Apache;
use strict;

use Carp qw//;
use Apache::Constants;
require Apache::Request;
require Apache::URI;

sub LJ::Request::OK                        { return Apache::Constants::OK() }
sub LJ::Request::REDIRECT                  { return Apache::Constants::REDIRECT() }
sub LJ::Request::DECLINED                  { return Apache::Constants::DECLINED() }
sub LJ::Request::FORBIDDEN                 { return Apache::Constants::FORBIDDEN() }
sub LJ::Request::HTTP_NOT_MODIFIED         { return Apache::Constants::HTTP_NOT_MODIFIED() }
sub LJ::Request::HTTP_MOVED_PERMANENTLY    { return Apache::Constants::HTTP_MOVED_PERMANENTLY() }
sub LJ::Request::HTTP_MOVED_TEMPORARILY    { return Apache::Constants::HTTP_MOVED_TEMPORARILY() }
sub LJ::Request::M_TRACE                   { return Apache::Constants::M_TRACE() }
sub LJ::Request::M_OPTIONS                 { return Apache::Constants::M_OPTIONS() }
sub LJ::Request::NOT_FOUND                 { return Apache::Constants::NOT_FOUND() }
sub LJ::Request::SERVER_ERROR              { return Apache::Constants::SERVER_ERROR() }
sub LJ::Request::BAD_REQUEST               { return Apache::Constants::BAD_REQUEST() }

my $instance = '';

sub _die_if_no_request {
    Carp::confess("Request is not provided to LJ::Request") unless $instance;
}

sub LJ::Request::request { $instance }
sub LJ::Request::r {
    _die_if_no_request();
    return $instance->{r};
}


sub LJ::Request::instance { Carp::confess("use 'request' instead") }
sub LJ::Request::init {
    my $class = shift;
    my $r     = shift;

    $instance = bless {}, $class;
    $instance->{apr} = Apache::Request->new($r);
    $instance->{r} = $r;
    return $instance;
}

sub LJ::Request::is_inited {
    return $instance ? 1 : 0;
}

sub LJ::Request::update_mtime {
    my $class = shift;
    die "Request is not provided to LJ::Request" unless $instance;
    return $instance->{apr}->update_mtime(@_);
}

sub LJ::Request::set_last_modified {
    my $class = shift;
    _die_if_no_request();
    return $instance->{apr}->set_last_modified(@_);
}

sub LJ::Request::request_time {
    my $class = shift;
    _die_if_no_request();
    return $instance->{apr}->request_time();
}

sub LJ::Request::meets_conditions {
    my $class = shift;
    _die_if_no_request();
    return $instance->{apr}->meets_conditions();
}

sub LJ::Request::read {
    my $class = shift;
    _die_if_no_request();
    return $instance->{apr}->read(@_);
}

sub LJ::Request::is_main {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->is_main(@_);
}

sub LJ::Request::main {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->main(@_);
}

sub LJ::Request::dir_config {
    my $class = shift;
    _die_if_no_request();
    return $instance->{apr}->dir_config(@_);
}

sub LJ::Request::header_only {
    my $class = shift;
    _die_if_no_request();
    return $instance->{apr}->header_only;
}

sub LJ::Request::content_languages {
    my $class = shift;
    _die_if_no_request();
    return $instance->{apr}->content_languages(@_);
}

sub LJ::Request::register_cleanup {
    my $class = shift;
    _die_if_no_request();
    return $instance->{apr}->register_cleanup(@_);
}

sub LJ::Request::path_info {
    my $class = shift;
    _die_if_no_request();
    return $instance->{apr}->path_info(@_);
}

sub LJ::Request::args {
    my $class = shift;
    _die_if_no_request();
    return $instance->{apr}->args(@_);
}

sub LJ::Request::method {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->method;
}

sub LJ::Request::bytes_sent {
    my $class = shift;
    _die_if_no_request();
    $instance->{r}->bytes_sent(@_);
}

sub LJ::Request::document_root {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->document_root;
}

sub LJ::Request::finfo {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->finfo;
}

sub LJ::Request::filename {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->filename(@_);
}

sub LJ::Request::add_httpd_conf {
    my $class = shift;
    Apache->httpd_conf(@_);
}

sub LJ::Request::is_initial_req {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->is_initial_req(@_);
}

sub LJ::Request::push_handlers_global {
    my $class = shift;
    Apache->push_handlers(@_);
}

sub LJ::Request::push_handlers {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->push_handlers(@_);
}

sub LJ::Request::set_handlers {
    my $class = shift;
    _die_if_no_request();
    $instance->{r}->set_handlers(@_);
}

sub LJ::Request::handler {
    my $class = shift;
    _die_if_no_request();
    $instance->{r}->handler(@_);
}

sub LJ::Request::method_number {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->method_number(@_);
}

sub LJ::Request::status {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->status(@_);
}

sub LJ::Request::status_line {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->status_line(@_);
}

##
##
##
sub LJ::Request::free {
    my $class = shift;
    $instance = undef;
}


sub LJ::Request::notes {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->notes (@_);
}

sub LJ::Request::pnotes {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->pnotes (@_);
}

sub LJ::Request::parse {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->parse (@_);
}

sub LJ::Request::uri {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->uri (@_);
}

sub LJ::Request::hostname {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->hostname (@_);
}

sub LJ::Request::header_out {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->header_out (@_);
}

sub LJ::Request::headers_out {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->headers_out (@_);
}

sub LJ::Request::header_in {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->header_in (@_);
}

sub LJ::Request::headers_in {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->headers_in (@_);
}

sub LJ::Request::param {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->param (@_);
}

sub LJ::Request::no_cache {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->no_cache (@_);
}

sub LJ::Request::content_type {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->content_type (@_);
}

sub LJ::Request::pool {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->pool;
}

sub LJ::Request::connection {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->connection;
}

sub LJ::Request::output_filters {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->output_filters;
}

sub LJ::Request::print {
    my $class = shift;
    _die_if_no_request();
    $instance->{r}->print (@_);
}

sub LJ::Request::content_encoding {
    my $class = shift;
    _die_if_no_request();
    $instance->{r}->content_encoding(@_);
}

sub LJ::Request::send_http_header {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->send_http_header (@_)
}


sub LJ::Request::err_headers_out {
    my $class = shift;
    _die_if_no_request();
    $instance->{apr}->err_headers_out (@_)
}



## Returns Array (Key, Value, Key, Value) which can be converted to HASH.
## But there can be some params with the same name!
#
# TODO: do we need this and 'args' methods? they are much the same.
sub LJ::Request::get_params {
    my $class = shift;
    _die_if_no_request();
    my @params = $instance->{r}->args;
    return @params;
}

sub LJ::Request::post_params {
    my $class = shift;
    _die_if_no_request();

    ## $r->content
    ## The $r->content method will return the entity body read from the client,
    ## but only if the request content type is application/x-www-form-urlencoded.
    ## ...
    ## NOTE: you can only ask for this once, as the entire body is read from the client.
    return () if $instance->{r}->headers_in()->get("Content-Type") =~ m!^multipart/form-data!;

    return @{ $instance->{params} } if $instance->{params};
    my @params = $instance->{r}->content;
    $instance->{params} = \@params;
    return @params;
}


sub LJ::Request::add_header_out {
    my $class  = shift;
    my $header = shift;
    my $value  = shift;

    _die_if_no_request();
    
    $instance->{r}->err_headers_out->add($header, $value);
    $instance->{r}->headers_out->add($header, $value);

    return 1;
}

# TODO: maybe remove next method and use 'header_out' instead?
sub LJ::Request::set_header_out {
    my $class  = shift;
    my $header = shift;
    my $value  = shift;

    _die_if_no_request();

    $instance->{r}->err_header_out($header, $value);
    $instance->{r}->header_out($header, $value);

    return 1;
}

sub LJ::Request::unset_headers_in {
    my $class = shift;
    my $header = shift;
    
    _die_if_no_request();
    
    $instance->{r}->headers_in->unset($header);
}

sub LJ::Request::log_error {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->log_error(@_);
}

sub LJ::Request::remote_ip {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->connection()->remote_ip(@_);
}

sub LJ::Request::remote_host {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->connection()->remote_host;
}

sub LJ::Request::user {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->connection()->user;
}

sub LJ::Request::aborted {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->connection()->aborted;
}


sub LJ::Request::sendfile {
    my $class = shift;
    my $filename = shift;
    my $fh       = shift;

    _die_if_no_request();
    $instance->{r}->send_fd($fh);
    $fh->close();

}

sub LJ::Request::parsed_uri {
    my $class = shift;
    _die_if_no_request();
    $instance->{r}->parsed_uri; # Apache::URI
}

sub LJ::Request::current_callback {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->current_callback;
}

sub LJ::Request::child_terminate {
    my $class = shift;
    _die_if_no_request();
    return $instance->{r}->child_terminate;
}


1;
