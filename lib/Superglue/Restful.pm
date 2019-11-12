package Superglue::Restful;

=head1 NAME

Superglue::Restful - JSON-over-HTTP API suport routines

=head1 DESCRIPTION

This module provides helper functions for "restful" API clients, with
JSON encoding / decoding, tracing, error handling.

=cut

use warnings;
use strictures 2;

use Carp;
use HTTP::Request::Common qw();
use JSON;
use LWP::UserAgent;
use URI;

# un-exported utilities

sub censor_ripe {
	my $uri = shift;
	# gross hack to mitigate design error in RIPE REST API
	my $urx = $uri =~ s{([?]password=)[^&;]*}{${1}********}r;
	return ($uri,$urx);
}

sub croak_http {
	my $r = shift;
	return unless @_;
	my $summary = shift;
	my $detail = shift;
	my ($uri,$urx) = censor_ripe $r->request->uri;
	croak sprintf "%s\n%s %s\n%s\n%s",
	    $summary,
	    $r->request->method,
	    $urx,
	    $r->status_line,
	    $detail // '';
}

use Moo::Role;

our @SUPERGLUE_GETOPT = ();

our @SUPERGLUE_EXPORT = qw(
	DELETE
	GET
	PATCH
	POST
	PUT
	base_uri
	http_error
	json_error
	post_form
	user_agent
);

has base_uri => (
	is => 'rw',
    );

# underlying LWP::UserAgent
has user_agent => (
	is => 'ro',
	lazy => 1,
	default => sub {
		my $self = shift;
		$self->{user_agent} = LWP::UserAgent->new(
			agent => "Superglue",
			ssl_opts => { verify_hostname => 1 },
		    );
	},
    );

has http_error => (
	is => 'rw',
    );

has json_error => (
	is => 'rw',
    );

sub uri {
	my $self = shift;
	my $uri = shift;
	if (my $base = $self->base_uri) {
		return URI->new_abs($uri, $base);
	} else {
		return $uri;
	}
}

sub post_form {
	my $self = shift;
	my ($uri,$urx) = censor_ripe $self->uri(shift);
	$self->debug("post form $urx");
	my $req = HTTP::Request::Common::POST($uri,
	    'Content-Type' => 'form-data',
	    'Content' => [ @_ ]);
	$req->header('Authorization' => $self->{login}->{authorization})
	    if $self->{login}->{authorization};
	my $r = $self->user_agent->request($req);
	$self->debug($r->status_line);
	return $r->content unless $r->is_error;
	croak_http $r, "request failed", $r->content;
}

sub request {
	my $self = shift;
	my $method = shift;
	my ($uri,$urx) = censor_ripe $self->uri(shift);
	$self->debug("$method $urx", @_);
	my $req = HTTP::Request->new($method, $uri);
	$req->header('Accept' => 'application/json');
	$req->header('Authorization' => $self->{login}->{authorization})
	    if $self->{login}->{authorization};
	$req->header('Content-Type' => 'application/json') if @_;
	$req->content(encode_json shift) if @_;
	my $r = $self->user_agent->request($req);
	my $body = $r->content;
	return croak_http $r,
	    $self->http_error
	    ? $self->http_error->($r)
	    : ("response is not JSON" => $body)
	    unless $body =~ m(^[[{]);
	my $json = decode_json $body;
	# hack: WebDriver seems to wrap everything
	$json = $json->{value}
	    if 'HASH' eq ref $json
	    and exists $json->{value}
	    and 1 == scalar keys %$json;
	$self->debug($r->status_line, $json);
	return $json unless $r->is_error;
	return croak_http $r,
	    $self->json_error
	    ? $self->json_error->($json)
	    : ("request failed" => to_json $json,
		{ allow_nonref => 1, canonical => 1, pretty => 1 });
}

sub DELETE {
	return shift->request(DELETE => @_);
}

sub GET {
	return shift->request(GET => @_);
}

sub POST {
	return shift->request(POST => @_);
}

sub PATCH {
	return shift->request(PATCH => @_);
}

sub PUT {
	return shift->request(PUT => @_);
}

1;
