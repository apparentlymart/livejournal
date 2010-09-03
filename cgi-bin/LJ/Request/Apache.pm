package LJ::Request::Apache;
use strict;

use Carp qw//;
use Apache::Constants;
require Apache;
require Apache::Request;
require Apache::URI;
require Apache::File;
require Apache::Table;

sub LJ::Request::OK                        { return Apache::Constants::OK() }
sub LJ::Request::DONE                      { return Apache::Constants::DONE() }
sub LJ::Request::REDIRECT                  { return Apache::Constants::REDIRECT() }
sub LJ::Request::DECLINED                  { return Apache::Constants::DECLINED() }
sub LJ::Request::FORBIDDEN                 { return Apache::Constants::FORBIDDEN() }
sub LJ::Request::HTTP_NOT_MODIFIED         { return Apache::Constants::HTTP_NOT_MODIFIED() }
sub LJ::Request::HTTP_MOVED_PERMANENTLY    { return Apache::Constants::HTTP_MOVED_PERMANENTLY() }
sub LJ::Request::HTTP_MOVED_TEMPORARILY    { return Apache::Constants::HTTP_MOVED_TEMPORARILY() }
sub LJ::Request::HTTP_METHOD_NOT_ALLOWED   { return Apache::Constants::HTTP_METHOD_NOT_ALLOWED() }
sub LJ::Request::HTTP_BAD_REQUEST          { return Apache::Constants::HTTP_BAD_REQUEST() }
sub LJ::Request::M_TRACE                   { return Apache::Constants::M_TRACE() }
sub LJ::Request::M_OPTIONS                 { return Apache::Constants::M_OPTIONS() }
sub LJ::Request::M_PUT                     { return Apache::Constants::M_PUT() }
sub LJ::Request::M_POST                    { return Apache::Constants::M_POST() }
sub LJ::Request::NOT_FOUND                 { return Apache::Constants::NOT_FOUND() }
sub LJ::Request::SERVER_ERROR              { return Apache::Constants::SERVER_ERROR() }
sub LJ::Request::BAD_REQUEST               { return Apache::Constants::BAD_REQUEST() }
sub LJ::Request::HTTP_GONE                 { return Apache::Constants::NOT_FOUND() }
sub LJ::Request::AUTH_REQUIRED             { return Apache::Constants::AUTH_REQUIRED() }

my $instance = '';

sub LJ::Request::_get_instance {
    my $class = shift;

    return $class if ref $class;

    Carp::confess("Request is not provided to LJ::Request") unless $instance;
    return $instance;
}

sub LJ::Request::interface_name { 'Apache' }

sub LJ::Request::request { $instance }

sub LJ::Request::r {
    return shift->_get_instance()->{r};
}

sub LJ::Request::apr {
    return shift->_get_instance()->{apr};
}

sub LJ::Request::_new {
    my $class = shift;
    my $r     = shift;

    return bless {
        r   => $r,
        apr => Apache::Request->new($r),
    }, $class;
}

sub LJ::Request::instance { Carp::confess("use 'request' instead") }

sub LJ::Request::init {
    my $class = shift;
    my $r     = shift;

    # second init within a same request.
    # Request object may differ between handlers.
    if ($class->is_inited){
        # NOTE. this is not good approach. becouse we would have Apache::Request based on other $r object.
        $instance->{r} = $r;
        return $instance;
    }

    $instance = LJ::Request->_new($r);

    # Temporary HACK
    if ($r->method eq 'POST'){
        #$r->headers_in()->set("Content-Type", "multipart/form-data");
    }
    
    return $instance;
}

sub LJ::Request::prev {
    my $class = shift;
    return LJ::Request->_new($class->r()->prev(@_));
}

sub LJ::Request::is_inited {
    return $instance ? 1 : 0;
}

sub LJ::Request::update_mtime {
    my $class = shift;
    return $class->apr()->update_mtime(@_);
}

sub LJ::Request::set_last_modified {
    my $class = shift;
    return $class->r()->set_last_modified(@_);
}

sub LJ::Request::request_time {
    my $class = shift;
    return $class->r()->request_time();
}

sub LJ::Request::meets_conditions {
    my $class = shift;
    return $class->r()->meets_conditions();
}

sub LJ::Request::read {
    my $class = shift;
    return $class->apr()->read(@_);
}

sub LJ::Request::is_main {
    my $class = shift;
    return $class->r()->is_main(@_);
}

sub LJ::Request::main {
    my $class = shift;
    return $class->r()->main(@_);
}

sub LJ::Request::dir_config {
    my $class = shift;
    return $class->r()->dir_config(@_);
}

sub LJ::Request::header_only {
    my $class = shift;
    return $class->r()->header_only;
}

sub LJ::Request::content_languages {
    my $class = shift;
    return $class->r()->content_languages(@_);
}

sub LJ::Request::register_cleanup {
    my $class = shift;
    return $class->r()->register_cleanup(@_);
}

sub LJ::Request::path_info {
    my $class = shift;
    return $class->r()->path_info(@_);
}

sub LJ::Request::args {
    my $class = shift;
    return $class->apr()->args(@_);
}

sub LJ::Request::method {
    my $class = shift;
    $class->r()->method;
}

sub LJ::Request::bytes_sent {
    my $class = shift;
    $class->r()->bytes_sent(@_);
}

sub LJ::Request::document_root {
    my $class = shift;
    $class->r()->document_root;
}

sub LJ::Request::finfo {
    my $class = shift;
    $class->r()->finfo;
}

sub LJ::Request::filename {
    my $class = shift;
    $class->r()->filename(@_);
}

sub LJ::Request::add_httpd_conf {
    my $class = shift;
    Apache->httpd_conf(@_);
}

sub LJ::Request::is_initial_req {
    my $class = shift;
    $class->r()->is_initial_req(@_);
}

sub LJ::Request::push_handlers_global {
    my $class = shift;
    Apache->push_handlers(@_);
}

sub LJ::Request::push_handlers {
    my $class = shift;
    my $self = $class->_get_instance();

    # $instance->{r}->push_handlers(@_);
    return ($_[0] =~ /PerlHandler/)
        ? $self->set_handlers(@_)
        : Apache->request->push_handlers(@_);
}

sub LJ::Request::set_handlers {
    my $class = shift;
    my $r = $class->r();
    my $handler_name = shift;
    my $handlers = (ref $_[0] eq 'ARRAY') ? shift : [@_]; # second arg should be an arrayref.
    if ($handler_name eq 'PerlCleanupHandler') {
        $r->push_handlers($handler_name, $_) foreach (@$handlers);
    } else {
        $r->set_handlers($handler_name, $handlers);
    }
}

sub LJ::Request::handler {
    my $class = shift;
    $class->r()->handler(@_);
}

sub LJ::Request::method_number {
    my $class = shift;
    return $class->r()->method_number(@_);
}

sub LJ::Request::status {
    my $class = shift;
    return $class->r()->status(@_);
}

sub LJ::Request::status_line {
    my $class = shift;
    return $class->r()->status_line(@_);
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
    $class->apr()->notes (@_);
}

sub LJ::Request::pnotes {
    my $class = shift;
    $class->apr()->pnotes (@_);
}

sub LJ::Request::parse {
    my $class = shift;
    $class->apr()->parse (@_);
}

sub LJ::Request::uri {
    my $class = shift;
    $class->apr()->uri (@_);
}

sub LJ::Request::hostname {
    my $class = shift;
    $class->apr()->hostname (@_);
}

sub LJ::Request::header_out {
    my $class = shift;
    $class->apr()->header_out (@_);
}

sub LJ::Request::headers_out {
    my $class = shift;
    $class->apr()->headers_out (@_);
}

sub LJ::Request::header_in {
    my $class = shift;
    $class->apr()->header_in (@_);
}

sub LJ::Request::headers_in {
    my $class = shift;
    $class->apr()->headers_in (@_);
}

sub LJ::Request::param {
    my $class = shift;
    $class->apr()->param (@_);
}

sub LJ::Request::no_cache {
    my $class = shift;
    $class->apr()->no_cache (@_);
}

sub LJ::Request::content_type {
    my $class = shift;
    $class->apr()->content_type (@_);
}

sub LJ::Request::pool {
    my $class = shift;
    $class->apr()->pool;
}

sub LJ::Request::connection {
    my $class = shift;
    $class->apr()->connection;
}

sub LJ::Request::output_filters {
    my $class = shift;
    $class->apr()->output_filters;
}

sub LJ::Request::print {
    my $class = shift;
    $class->r()->print(@_);
}

sub LJ::Request::content_encoding {
    my $class = shift;
    $class->r()->content_encoding(@_);
}

sub LJ::Request::send_http_header {
    my $class = shift;
    $class->apr()->send_http_header(@_);
}


sub LJ::Request::err_headers_out {
    my $class = shift;
    $class->apr()->err_headers_out (@_)
}



## Returns Array (Key, Value, Key, Value) which can be converted to HASH.
## But there can be some params with the same name!
#
# TODO: do we need this and 'args' methods? they are much the same.
sub LJ::Request::get_params {
    my $class = shift;
    my @params = $class->r()->args;
    return @params;
}

sub LJ::Request::post_params {
    my $class = shift;
    my $self = $class->_get_instance();

    ## $r->content
    ## The $r->content method will return the entity body read from the client,
    ## but only if the request content type is application/x-www-form-urlencoded.
    ## ...
    ## NOTE: you can only ask for this once, as the entire body is read from the client.
    #return () if $instance->{r}->headers_in()->get("Content-Type") =~ m!^multipart/form-data!;

    return @{ $self->{params} } if $self->{params};  

    my @params = $self->_parse_post();
    if(@params == 1){
        $self->{raw_content} = shift @params;   
    }
    $self->{params} = \@params;
    return @params;
}

sub LJ::Request::raw_content {
    my $class = shift;
    my $self = $class->_get_instance();
    return if $self->post_params;
    return $self->{raw_content};
} 

sub LJ::Request::add_header_out {
    my $class  = shift;
    my $header = shift;
    my $value  = shift;

    my $r = $class->r();
    $r->err_headers_out->add($header, $value);
    $r->headers_out->add($header, $value);

    return 1;
}

# TODO: maybe remove next method and use 'header_out' instead?
sub LJ::Request::set_header_out {
    my $class  = shift;
    my $header = shift;
    my $value  = shift;

    my $r = $class->r();    
    $r->err_header_out($header, $value);
    $r->header_out($header, $value);

    return 1;
}

sub LJ::Request::unset_headers_in {
    my $class = shift;
    my $header = shift;
    
    my $r = $class->r();
    $r->headers_in->unset($header);
}

sub LJ::Request::log_error {
    my $class = shift;
    return $class->r()->log_error(@_);
}

sub LJ::Request::remote_ip {
    my $class = shift;
    return $class->r()->connection()->remote_ip(@_);
}

sub LJ::Request::remote_host {
    my $class = shift;
    return $class->r()->connection()->remote_host;
}

sub LJ::Request::user {
    my $class = shift;
    return $class->r()->connection()->user;
}

sub LJ::Request::aborted {
    my $class = shift;
    return $class->r()->connection()->aborted;
}


sub LJ::Request::sendfile {
    my $class = shift;
    my $filename = shift;
    my $fh       = shift;

    $class->r()->send_fd($fh);
    $fh->close();

}

sub LJ::Request::upload {
    my $class = shift;
    return $class->apr()->upload(@_);
}

sub LJ::Request::parsed_uri {
    my $class = shift;
    $class->r()->parsed_uri; # Apache::URI
}

sub LJ::Request::current_callback {
    my $class = shift;
    return $class->r()->current_callback;
}

sub LJ::Request::child_terminate {
    my $class = shift;
    return $class->r()->child_terminate;
}

sub LJ::Request::_parse_post {
    my $class = shift;
    my $r = $class->r();
    my $apr = $class->apr();
    
    my $method = $r->method;
    return if $method eq 'GET'; # unless POST PUT DELETE HEAD
    my $host = $r->headers_in()->get("Host");
    my $uri = $r->uri;
    
    ## apreq parses only this encoding methods.
    my $content_type = $r->headers_in()->get("Content-Type");
    if ($content_type =~ m!^application/(json|xml)!i){
        my $content;
        $apr->read($content, $r->headers_in()->get('Content-Length')) if $r->headers_in()->get('Content-Length');
        return $content;
    }elsif ($content_type !~ m!^application/x-www-form-urlencoded!i &&
        $content_type !~ m!^multipart/form-data!i)
    {
        ## hack: if this is a POST request, and App layer asked us
        ## for params, pretend that encoding is default 'application/x-www-form-urlencoded'
        ## Some clients that use flat protocol issue malformed headers,
        ## so don't even make a warn.
        if ($uri ne '/interface/flat') {
            warn "Changing content-type of POST ($host$uri) from $content_type to default";
        }
        $r->headers_in()->set("Content-Type", "application/x-www-form-urlencoded");
    }
    
    return unless $method eq 'POST';
   
    my $qs = $r->args;
    $r->args(''); # to exclude GET params from Apache::Request object.
                  # it allows us to separate GET params and POST params.
                  # otherwise Apache::Request's "parms" method returns them together.

    my $parse_res = $apr->parse;
    # set original QUERY_STRING back
    $r->args($qs);
    
    if (!$parse_res eq OK) {
        warn "Can't parse POST data ($host$uri), Content-Type=$content_type";
        return;
    }
    
    my @params = ();
    foreach my $name ($apr->param){
        foreach my $val ($apr->param($name)){
            push @params => ($name, $val);
        }
    }
    return @params;
}

1;
