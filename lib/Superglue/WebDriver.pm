package Superglue::WebDriver;

=head1 NAME

Superglue::WebDriver - web browser remote control

=head1 DESCRIPTION

The W3C WebDriver protocol is a standard way to control a browser for
testing or automation, by making JSON-over-HTTP requests. This
WebDriver client is known to work with B<geckodriver> and B<Firefox>.

This module is a L<Moo::Role> mixin that relies on L<Superglue::Restful>
for lower-level HTTP and JSON support.

=cut

use warnings;
use strict;

use Carp;
use Sys::Syslog qw(:macros);

# Utility subtroutines that are not exported as methods.

# A special JSON key name whose value is an element UUID
my $ELEMENT = 'element-6066-11e4-a52e-4f735466cecf';

# This handles the cases explained under LOCATING HTML ELEMENTS below,
# except for previously-located elements which are handled by $sg->elem.
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

# Check that the argument is previously located element.
sub is_elem {
	my $json = shift;
	return ref $json && exists $json->{$ELEMENT};
}

use Moo::Role;

requires qw(
	DEL
	GET
	POST
	verbose
	user_agent
);

our @SUPERGLUE_GETOPT = qw{
	foreground!
	host=s
	port=i
	reconnect!
	retain!
	session=s
};

has webdriver => (
	is => 'ro',
    );

has foreground => (
	is => 'ro',
    );

has reconnect => (
	is => 'ro',
    );

has retain => (
	is => 'ro',
    );

has host => (
	is => 'ro',
	default => '127.0.0.1',
    );

has port => (
	is => 'ro',
	default => 4444,
    );

has session => (
	is => 'ro',
    );

has driver_pid => (
	is => 'rw',
    );

before DEMOLISH => sub {
	my $self = shift;
	return unless $self->{webdriver};
	return if $self->retain;
	# delete WebDriver session
	$self->DEL('');
	# clean up subprocess
	kill INT => $self->driver_pid if $self->driver_pid;
};

=head1 ATTRIBUTES

When constructing a L<Superglue> object, you can provide the following
attributes to configure WebDriver.

=over

=item webdriver => 1

Enable WebDriver. The attributes listed below are ignored if WebDriver
is not enabled.

=item foreground => 1

Start Firefox with a GUI, so you can watch what happens.
By default Firefox is passed the B<-headless> option.

=item host => $ip_address

IP address of the WebDriver server, by default C<127.0.0.1>.
This is used in WebDriver URLs, and is passed to
C<geckodriver --host>.

=item port => $port_number

Port of the WebDriver server, by default C<4444>.
This is used in WebDriver URLs, and is passed to
C<geckodriver --port>.

=item reconnect => 1

Connect to an existing WebDriver server, otherwise the default is to
start a new instance of B<geckodriver>. We always reconnect if the
B<session> option is given.

=item retain => 1

Do not close the session when the script is complete. By default the session
is closed, which makes the browser quit.

=item session => $uuid

Re-use an existing WebDriver session with the given UUID. This avoids
starting a new instance of Firefox.

=back

=cut

after BUILD => sub {
	my $self = shift;
	return unless $self->{webdriver};
	$self->base_uri(sprintf "http://%s:%s/", $self->host, $self->port);
	unless ($self->session or $self->reconnect) {
		$self->driver_pid(fork);
		$self->error("fork: $!") unless defined $self->driver_pid;
		if ($self->driver_pid == 0) {
			my @cmd = qw(geckodriver);
			push @cmd, '--host' => $self->host;
			push @cmd, '--port' => $self->port;
			if ($self->verbosity < LOG_INFO) {
				push @cmd, '--log' => 'fatal'
			} else {
				push @cmd, '--log' => 'trace'
			}
			exec @cmd or die "exec @cmd: $!\n";
		}
	}
	unless ($self->session) {
		my $caps = {};
		# allow 2 seconds when waiting for elements to appear
		$caps->{timeouts}->{implicit} = 2_000;
		# default page load timeout is 5 minutes
		$caps->{timeouts}->{pageLoad} = 30_000;
		# annoyingly, geckodriver returns a moz:headless capability
		# to us, but we have to write it this way in a request
		$caps->{'moz:firefoxOptions'}->{args}
		    = [ '-headless' ] unless $self->foreground;
		# empty prefix for first request
		my $r = $self->POST('/session', {
			capabilities => { alwaysMatch => $caps }
		    });
		$self->{session} = $r->{sessionId};
		$self->error_f("could not establish WebDriver session to %s",
			       $self->base_uri)
		    unless defined $self->session;
	}
	$self->base_uri(sprintf "http://%s:%s/session/%s/",
			$self->host, $self->port, $self->session);
};

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

Located elements are returned by C<$sg->elem> and other methods.

=back

=head1 METHODS

=over

=cut

our @SUPERGLUE_EXPORT = qw{
	navigate
	page_title
	js_sync
	elem
	elems
	sub_elem
	has_elem
	elem_attr
	elem_prop
	elem_text
	elem_selected
	clear
	click
	fill
	pause
	wait_for
};

=item $sg->navigate($url)

Send the web browser to the I<$url>. Returns null.

=cut

sub navigate {
	shift->POST('url', { url => shift });
}

=item $sg->page_title

Returns the text of the page title.

=cut

sub page_title {
	return shift->GET('title');
}

=item $sg->js_sync($script)

Run I<$script> in the browser and wait for it to complete.

=cut

# I am not sure how the arguments are used - the webdriver
# spec seems not to include them when calling the script.

sub js_sync {
	shift->POST('execute/sync', { script => shift, args => [ @_ ] });
}

=item $sg->elem($locator)

Returns a located element, as described under L</LOCATING HTML ELEMENTS>
above.

=cut

sub elem {
	my $self = shift;
	my $elem = shift;
	return $elem if is_elem $elem; # pass through
	return $self->POST('element', using $elem);
}

=item $sg->elems($locator)

Returns a reference to an array of located elements.

=cut

sub elems {
	return shift->POST('elements', using shift);
}

=item $sg->has_elem($locator)

Returns true if an element was located. This is an abbreviation for
calling C<$sg-E<gt>elems> and checking for a non-empty result.

=cut

sub has_elem {
	my $elems = shift->elems(shift);
	return scalar @$elems;
}

=item $sg->elem_request($method, $locator, $action, $body)

Perform I<$action> on the element identified by I<$locator>. The
I<$body> is used if the HTTP I<$method> needs it, like C<POST>.
WebDriver element action URLs are like
C</session/$sessionID/element/$elemID/$action>.

=cut

sub elem_request {
	my $self = shift;
	my $method = shift;
	my $json = $self->elem(shift);
	my $action = shift;
	croak sprintf "Not an element: %s", $self->ppjson($json)
	    unless is_elem $json;
	my $url = sprintf 'element/%s/%s', $json->{$ELEMENT}, $action;
	return $self->request($method, $url, @_);
}

=item $sg->sub_elem($ancestor, $descendent)

Locate a I<$descendent> element relative to an I<$ancestor>.
(Often the I<$ancestor> will have previously been located by another subroutine,
but this is not required.)

=cut

sub sub_elem {
	return shift->elem_request(POST => shift, 'element', using shift);
}

=item $sg->sub_elems($ancestor, $descendent)

Locate I<$descendent> elements relative to an I<$ancestor>.
Returns a reference to an array of located elements.

=cut

sub sub_elems {
	return shift->elem_request(POST => shift, 'elements', using shift);
}

=item $sg->click($locator)

Click on an element. Returns null.

=cut

sub click {
	return shift->elem_request(POST => shift, 'click', {})
}

=item $sg->elem_attr($locator, $attribute)

Returns the I<$attribute> of the element.

=cut

sub elem_attr {
	return shift->elem_request(GET => shift, 'attribute/'.shift);
}

=item $sg->elem_prop($locator, $property)

Returns the I<$property> of the element.

=cut

sub elem_prop {
	return shift->elem_request(GET => shift, 'property/'.shift);
}

=item $sg->elem_tag($locator)

Returns the tag name of the element.

=cut

sub elem_tag {
	return shift->elem_request(GET => shift, 'name');
}

=item $sg->elem_text($locator)

Returns the rendered text in the element as a string.

=cut

sub elem_text {
	return shift->elem_request(GET => shift, 'text');
}

=item $sg->elem_selected($locator)

Returns a boolean corresponding to whether a form element is selected.

=cut

sub elem_selected {
	return shift->elem_request(GET => shift, 'selected');
}

=item $sg->clear($locator)

Clear a form element. Returns null.

=cut

sub clear {
	return shift->elem_request(POST => shift, 'clear', {});
}

=item $sg->fill($elem1 => $value1, $elem2 => $value2 ...)

Fill in a form. The arguments are a list of pairs, consisting of an element
locator for a form element and the value to insert into it. Each element is
cleared before the value is inserted. Returns null.

=cut

sub fill {
	my $self = shift;
	while (@_) {
		my $elem = $self->elem(shift);
		my $tag = $self->elem_tag($elem);
		my $type = $self->elem_attr($elem, 'type');
		my $texty = defined $type
		    && grep { $type eq $_ }
		    qw(email number password search tel text url);
		$self->clear($elem) if $tag eq 'textarea' or $texty;
		$self->elem_request(POST => $elem, 'value', { text => shift });
	}
}

=item $sg->wait_for(sub { ... })

Wait for some condition to succeed. The subroutine must return a
boolean value, which is typically the result of C<$sg-E<gt>has_elem>
test(s). The subroutine is run every 0.1 seconds until it returns
true; if it does not do so within 10 seconds then C<$sg-E<gt>wait_for>
croaks.

=cut

sub wait_for {
	my $self = shift;
	my $test = shift;
	for (1..100) {
		return if $test->();
		select undef, undef, undef, 0.1;
	}
	$self->verbosity(LOG_INFO);
	$test->();
	croak "timed out waiting for test to succeed";
}

=back

=head1 ERRORS

The methods call C<croak> when they fail; see L<Carp(3)>.

=head1 SEE ALSO

L<Superglue(3pm)>, L<Superglue::Restful(3pm)>

The W3C WebDriver protocol specification L<https://www.w3.org/TR/webdriver1/>

Mozilla Firefox B<geckodriver> L<https://github.com/mozilla/geckodriver>

=head1 AUTHOR

Written by Tony Finch <fanf2@cam.ac.uk> <dot@dotat.at>
at Cambridge University Information Services.
L<https://opensource.org/licenses/0BSD>

=cut

1;
