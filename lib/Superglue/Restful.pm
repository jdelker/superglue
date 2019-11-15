package Superglue::Restful;

=head1 NAME

Superglue::Restful - JSON-over-HTTP API suport routines

=head1 DESCRIPTION

This module provides helper functions for "restful" API clients, with
JSON encoding / decoding, tracing, error handling.

The following attributes and methods are incorporated into the main
Superglue object.

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

# no extra command-line options here
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

=head1 HTTP REQUESTS

=over

=item $reply = $sg->request(METHOD => $uri, $body)

The general form of a Superglue::Restful HTTP request is

=over

=item * convert the optional C<$body> to JSON;

=item * add an C<Authorization> header using C<$sg-E<gt>login-E<gt>{authorization}> if that is set;

=item * perform the request;

=item * check the response for problems (see L</ERROR HANDLING> below);

=item * return the decoded JSON object.

=back

=cut

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

=item $json = $sg->DELETE($uri)

=item $json = $sg->GET($uri)

=item $json = $sg->PATCH($uri, $body)

=item $json = $sg->POST($uri, $body)

=item $json = $sg->PUT($uri, $body)

Abbreviated versions of C<$sg-E<gt>request()>

=cut

sub DELETE {
	return shift->request(DELETE => @_);
}

sub GET {
	return shift->request(GET => @_);
}

sub PATCH {
	return shift->request(PATCH => @_);
}

sub POST {
	return shift->request(POST => @_);
}

sub PUT {
	return shift->request(PUT => @_);
}

=item $sg->post_form($url, %fields)

Send an HTML-form-style request. There is no JSON encoding or decoding
and the error handling hooks are not called.

An C<Authorization> header is added using
C<$sg-E<gt>login-E<gt>{authorization}> if that is set.

=cut

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

=back

=head1 ERROR HANDLING

If you do not set an error handling hook, C<$sg-E<gt>request()> will
croak with a message including:

=over

=item * a summary line

=item * the request method and URI

=item * the response status line

=item * more details about the error

=back

An error hook can return a summary and optional details to change the
error message. For example, you can use this to extract an error
message from a JSON response, so that it is formatted more nicely.

An error hook can return nothing to stop C<$sg-E<gt>request()> from
croaking; instead it will also return nothing. You can use this to do
your own error handling.

=over

=item $sg->http_error(sub { my $r = shift; ... })

This hook is called when the HTTP response is not JSON. The argument
is the L<HTTP::Response> object. If the hook is not set, the summary
is "response is not JSON" and the detail is the response body.

=cut

has http_error => (
	is => 'rw',
    );

=item $sg->json_error(sub { my $json = shift; ... })

This hook is called when the HTTP status indicates an error. The
argument is the decoded JSON body. If the hook is not set, the summary
is "request failed" and the detail is the pretty-printed JSON.

=cut

has json_error => (
	is => 'rw',
    );

=back

=head1 MISCELLANEA

=head2 Relative URIs

=over

=item $sg->base_uri($sg->login->{url})

You can set the C<base_uri> attribute so that you can use relative
URLs when calling the HTTP request methods.

=cut

has base_uri => (
	is => 'rw',
    );


=item $absolute = $sg->uri($uri)

Resolves a URI relative to the C<base_uri> if that has been set,
otherwise C<$uri> should be absolute and it is returned unchanged.

=cut

sub uri {
	my $self = shift;
	my $uri = shift;
	if (my $base = $self->base_uri) {
		return URI->new_abs($uri, $base);
	} else {
		return $uri;
	}
}

=back

=head2 User Agent

=over

=item $sg->user_agent

For getting access to the underlying L<LWP::UserAgent> object.

=cut

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


=back

=head1 AUTHOR

Written by Tony Finch <fanf2@cam.ac.uk> <dot@dotat.at>
at Cambridge University Information Services.
L<https://opensource.org/licenses/0BSD>

=head1 SEE ALSO

L<superglue(1)>, L<ReGPG::Login>, L<Superglue(3pm)>,
L<Superglue::Contact>, L<Superglue::Delegation>,
L<Superglue::Restful(3pm)>, L<Superglue::WebDriver>

=cut

1;
