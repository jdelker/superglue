package WebDriver;

=head1 NAME

WebDriver - script-style web browser remote control

=head1 DESCRIPTION

The W3C WebDriver protocol is a standard way to control a browser for
testing or automation, by making JSON-over-HTTP requests. It is known
to work with B<geckodriver> and B<Firefox>.

This module provides script style helper functions for WebDriver
clients. "Script style" means that this module aims to minimize the
amount of boilerplate needed to use it. It uses global state to hold
things like the WebDriver session so there is no need to pass around
an object reference, and it exports a lot of subroutines that are
designed to be invoked in "poetry style" with a minimum of punctuation.

=cut

use warnings;
use strict;

use Carp;
use Exporter qw(import);
use JSON;
use LWP::UserAgent;

our @EXPORT = qw{
	webdriver_init
	navigate
	elem
	elems
	sub_elem
	has_elem
	elem_text
	click
	fill
	pause
	wait_for
};

# the special JSON key name whose value is an element UUID
my $ELEMENT = 'element-6066-11e4-a52e-4f735466cecf';

# used by all our HTTP requests
my $ua = LWP::UserAgent->new(agent => 'Superglue::WebDriver');

# global state

my $verbose;

my $session; # UUID of this session

my $wd; # base URL of WebDriver server
my $wds; # "$wd/session/$session"

my $driver_pid;
my $retain;

END {
	# delete WebDriver session
	$ua->delete($wds) if $wds and not $retain;
	# clean up subprocess
	kill INT => $driver_pid if $driver_pid;
}

########################################################################
#
#  utility functions for error handling and debug tracing
#

sub ppjson {
	return to_json shift, { allow_nonref => 1, pretty => 1 };
}

sub trace {
	return unless $verbose;
	printf "%s\n", shift;
	return unless @_;
	print ppjson @_;
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

sub unwrap {
	my $r = shift;
	my $body = $r->content;
	croak_http $r, 'WebDriver response is not JSON', $body
	    unless $body =~ m(^[{]);
	my $json = decode_json $body;
	# webdriver seems to wrap everything
	$json = $json->{value}
	    if exists $json->{value}
	    and 1 == scalar keys %$json;
	trace $r->status_line, $json;
	croak_http $r, 'WebDriver request failed', $json->{message}
	    if $r->is_error;
	return $json;
}

sub POST {
	my $uri = $wds.shift;
	my $json = shift;
	trace "POST $uri", $json;
	return unwrap $ua->post
	    ($uri,
	     'Content-Type' => 'text/json',
	     'Content' => encode_json $json);
}

sub GET {
	my $uri = $wds.shift;
	trace "GET $uri";
	return unwrap $ua->get($uri);
}

########################################################################

=head1 LOCATING HTML ELEMENTS

The WebDriver protocol allows you to locate elements using any of the
following strategies:

=over

=item C<css selector>

=item C<link text>

=item C<partial link text>

=item C<tag name>

=item C<xpath>

=back

Many of the subroutines in this library take element locators as arguments,
which can be:

=over

=item A pair of a strategy and a selector

The pair is represented as a hash ref containing one key and one value,
like C<{ I<STRATEGY> =E<gt> I<SELECTOR> }>.
The strategies are listed above.
The meaning of the selector depends on the strategy.

=item A string

This is an abbreviation for C<{ 'css selector' =E<gt> I<STRING> }>

=item A previously located element

Located elements are returned by C<elem> and other subroutines.

=back

=cut

# util: normalize a location strategy
sub using {
	my $elem = shift;
	# the argument is like { 'tag name' => 'h1' }
	# (wrong if there is more than one hash item!)
	return { using => keys %$elem,
		 value => values %$elem }
	    if ref $elem;
	# the usual case is just a string
	return { using => 'css selector',
		 value => $elem };
}

# util: a previously located element
sub is_elem {
	my $json = shift;
	return ref $json && exists $json->{$ELEMENT};
}

=head1 SUBROUTINES

=over

=item webdriver_init I<OPTIONS>

Starts a WebDriver session. This usually involves starting
B<geckodriver> which in turn starts Firefox.
OPTIONS is a list of pairs:

=over

=item foreground => I<BOOL>

Start Firefox with a GUI, so you can watch what happens.
By default Firefox is passed the B<-headless> option.

=item host => I<ADDRESS>

IP address of the WebDriver server, by default C<127.0.0.1>.
This is used in WebDriver URLs, and is passed to
C<geckodriver --host>.

=item port => I<NUMBER>

Port of the WebDriver server, by default C<4444>.
This is used in WebDriver URLs, and is passed to
C<geckodriver --port>.

=item reconnect => I<BOOL>

Connect to an existing WebDriver server, otherwise the default is to
start a new instance of B<geckodriver>. We always reconnect if the
B<session> option is given.

=item retain => I<BOOL>

Do not close the session when the script is complete. By default the session
is closed, which makes the browser quit.

=item session => I<UUID>

Re-use an existing WebDriver session with the given UUID. This avoids
starting a new instance of Firefox.

=item verbose => I<BOOL>

Enable debug logging.

=back

=cut

sub webdriver_init {
	my %opt = @_;
	$verbose = $opt{verbose};
	$retain = $opt{retain};
	my $host = $opt{host} // '127.0.0.1';
	my $port = $opt{port} // '4444';
	$wd = "http://$host:$port";
	if ($opt{session}) {
		$session = $opt{session};
	} else {
		unless ($opt{reconnect}) {
			$driver_pid = fork;
			die "fork: $!\n" unless defined $driver_pid;
			if ($driver_pid == 0) {
				my @cmd = qw(geckodriver);
				push @cmd, '--host' => $host;
				push @cmd, '--port' => $port;
				push @cmd, '--log' => 'trace'
				    if $opt{verbose};
				exec @cmd
				    or die "exec @cmd: $!\n";
			}
		}
		my $caps = {};
		# allow 2 seconds when waiting for elements to appear
		$caps->{timeouts}->{implicit} = 2_000;
		# default page load timeout is 5 minutes
		$caps->{timeouts}->{pageLoad} = 60_000;
		# annoyingly, geckodriver returns a moz:headless capability
		# to us, but we have to write it this way in a request
		$caps->{'moz:firefoxOptions'}->{args}
		    = [ '-headless' ] unless $opt{foreground};
		# empty prefix for first request
		$wds = '';
		my $r = POST "$wd/session", {
			capabilities => { alwaysMatch => $caps }
		    };
		$session = $r->{sessionId};
		die "could not establish WebDriver session to $wd\n"
		    unless defined $session;
	}
	$wds = "$wd/session/$session";
}

=item navigate I<URL>

Send the web browser to the I<URL>. Returns null.

=cut

sub navigate {
	POST '/url', { url => shift };
}

=item elem I<LOCATOR>

Returns a located element.

=cut

sub elem {
	my $elem = shift;
	return $elem if is_elem $elem; # pass through
	return POST '/element', using $elem;
}

=item elems I<LOCATOR>

Returns a reference to an array of located elements.

=cut

sub elems {
	return POST "/elements", using @_;
}

=item has_elem I<LOCATOR>

Returns true if an element was located.

=cut

sub has_elem {
	my $elems = elems @_;
	return scalar @$elems;
}

# util: url for an element-specific endpoint
sub elemurl {
	my $json = elem shift;
	return sprintf '/element/%s/%s',
	    $json->{$ELEMENT}, shift
	    if is_elem $json;
	croak sprintf "Not an element: %s", ppjson $json;
}

=item sub_elem I<ANCESTOR>, I<DESCENDENT>

Locate a I<DESCENDENT> element relative to an I<ANCESTOR>.
(Often the I<ANCESTOR> will have previously been located by another subroutine,
but this is not required.)

=cut

sub sub_elem {
	my $url = elemurl shift, 'element';
	return POST $url, using @_;
}

=item sub_elems I<ANCESTOR>, I<DESCENDENT>

Locate I<DESCENDENT> elements relative to an I<ANCESTOR>.
Returns a reference to an array of located elements.

=cut

sub sub_elems {
	my $url = elemurl shift, 'elements';
	return POST $url, using @_;
}

=item click I<LOCATOR>

Click on an element. Returns null.

=cut

sub click {
	my $url = elemurl shift, 'click';
	return POST $url, {};
}

=item elem_text I<LOCATOR>

Returns the rendered text in the element as a string.

=cut

sub elem_text {
	return GET elemurl shift, 'text';
}

=item fill I<ELEM> => I<VALUE>, I<ELEM> => I<VALUE> ...

Fill in a form. The arguments are a list of pairs, consisting of an element
locator for a form element and the value to insert into it. Returns null.

=cut

sub fill {
	while (@_) {
		my $url = elemurl shift, 'value';
		POST $url, { text => shift };
	}
}

=item wait_for I<SUB>

Wait for some condition to succeed. The I<SUB> is a reference to a subroutine
returning a boolean value, which is typically the result of C<has_elem>
test(s). The checks are run every 0.1 seconds until they succeed; if they do
not do so within 10 seconds then the C<wait_for> croaks.

=cut

sub wait_for {
	my $test = shift;
	for (1..100) {
		return if $test->();
		select undef, undef, undef, 0.1;
	}
	$verbose = 1;
	$test->();
	croak "timed out waiting for test to succeed";
}

=back

=head1 ERRORS

The subroutines call C<croak> when they fail; see L<Carp(3)>.

=head1 SEE ALSO

The W3C WebDriver protocol specification L<https://www.w3.org/TR/webdriver1/>

Mozilla Firefox B<geckodriver> L<https://github.com/mozilla/geckodriver>

=head1 AUTHOR

  Written by Tony Finch <dot@dotat.at> <fanf2@cam.ac.uk>
  at Cambridge University Information Services
  You may do anything with this. It has no warranty.
  <http://creativecommons.org/publicdomain/zero/1.0/>

=cut

1;
