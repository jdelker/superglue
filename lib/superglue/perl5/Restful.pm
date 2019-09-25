package Restful;

=head1 NAME

Restful - JSON-over-HTTP API suport routines

=head1 DESCRIPTION

This module provides helper functions for "restful" API clients, with
JSON encoding / decoding, tracing, error handling.

=cut

use warnings;
use strictures 2;

use Carp;
use JSON;
use LWP::UserAgent;
use Moo;
use POSIX;
use Time::HiRes qw(gettimeofday);

has verbose => (
	is => 'rw',
    );

has agent => (
	is => 'ro',
	required => 1,
    );

has uri => (
	is => 'ro',
	required => 1,
    );

has authorization => (
	is => 'ro',
    );

# underlying LWP::UserAgent
has ua => (
	is => 'ro',
	lazy => 1,
	default => sub {
		my $self = shift;
		my $agent = $self->agent;
		$self->{ua} = LWP::UserAgent->new(agent => "Superglue::$agent");
	},
    );

########################################################################
#
#  stateless utility functions
#

sub ppjson {
	return to_json shift,
	    { allow_nonref => 1, canonical => 1, pretty => 1 };
}

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

########################################################################
#
#  utility methods
#

sub trace {
	my $self = shift;
	return unless $self->verbose;
	my ($seconds, $microseconds) = gettimeofday;
	my $stamp = strftime "%F %T", localtime $seconds;
	printf "%s.%03d %s\n", $stamp, $microseconds/1000, shift;
	return unless @_;
	print ppjson @_;
}

sub request {
	my $self = shift;
	my $method = shift;
	my $uri = $self->uri.shift;
	$self->trace("$method $uri", @_);
	my $req = HTTP::Request->new($method, $uri);
	$req->header('Authorization' => $self->authorization)
	    if $self->authorization;
	$req->header('Content-Type' => 'application/json') if @_;
	$req->content(encode_json shift) if @_;
	my $r = $self->ua->request($req);
	my $agent = $self->agent;
	my $body = $r->content;
	croak_http $r, "$agent response is not JSON", $body
	    unless $body =~ m(^[[{]);
	my $json = decode_json $body;
	$json = { value => $json } if 'ARRAY' eq ref $json;
	# hack: WebDriver seems to wrap everything
	$json = $json->{value}
	    if exists $json->{value}
	    and 1 == scalar keys %$json;
	$self->trace($r->status_line, $json);
	# xxx: is this too specific to WebDriver?
	croak_http $r, "$agent request failed", $json->{message}
	    if $r->is_error;
	return $json;
}

########################################################################
#
#  public methods for restful requests
#

sub get {
	my $self = shift;
	return $self->request(GET => @_);
}

sub post {
	my $self = shift;
	return $self->request(POST => @_);
}

sub patch {
	my $self = shift;
	return $self->request(PATCH => @_);
}

sub put {
	my $self = shift;
	return $self->request(PUT => @_);
}

########################################################################

1;
