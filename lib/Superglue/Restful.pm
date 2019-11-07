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
use JSON;
use LWP::UserAgent;

# un-exported utilities

sub croak_http {
	my $r = shift;
	my $summary = shift;
	my $detail = shift;
	croak sprintf "%s\n%s %s\n%s\n%s",
	    $summary,
	    $r->request->method,
	    $r->request->uri,
	    $r->status_line,
	    $detail // '';
}

use Moo::Role;

our @SUPERGLUE_GETOPT = ();

our @SUPERGLUE_EXPORT = qw(
	GET
	PATCH
	POST
	PUT
	base_uri
	json_error
);

has base_uri => (
	is => 'rw',
    );

# underlying LWP::UserAgent
has ua => (
	is => 'ro',
	lazy => 1,
	default => sub {
		my $self = shift;
		$self->{ua} = LWP::UserAgent->new(agent => "Superglue");
	},
    );

has json_error => (
	is => 'rw',
    );

sub request {
	my $self = shift;
	my $method = shift;
	my $uri = $self->base_uri.shift;
	$self->debug("$method $uri", @_);
	my $req = HTTP::Request->new($method, $uri);
	$req->header('Accept' => 'application/json');
	$req->header('Authorization' => $self->login->{authorization})
	    if $self->login->{authorization};
	$req->header('Content-Type' => 'application/json') if @_;
	$req->content(encode_json shift) if @_;
	my $r = $self->ua->request($req);
	my $body = $r->content;
	croak_http $r, "response is not JSON", $body
	    unless $body =~ m(^[[{]);
	my $json = decode_json $body;
	# hack: WebDriver seems to wrap everything
	$json = $json->{value}
	    if 'HASH' eq ref $json
	    and exists $json->{value}
	    and 1 == scalar keys %$json;
	$self->debug($r->status_line, $json);
	return $json unless $r->is_error;
	my $message = $self->json_error
	    ? $self->json_error->($json)
	    : to_json $json,
	    { allow_nonref => 1, canonical => 1, pretty => 1 };
	croak_http $r, "request failed", $message;
}

sub GET {
	my $self = shift;
	return $self->request(GET => @_);
}

sub POST {
	my $self = shift;
	return $self->request(POST => @_);
}

sub PATCH {
	my $self = shift;
	return $self->request(PATCH => @_);
}

sub PUT {
	my $self = shift;
	return $self->request(PUT => @_);
}

1;
