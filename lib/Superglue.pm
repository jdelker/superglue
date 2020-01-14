package Superglue;

=head1 NAME

Superglue - framework for domain registration management scripts

=head1 SYNOPSIS

  # object-oriented

  use Superglue;

  my $sg = Superglue->new(...);

  # script-style

  use Superglue qw(:script);

=head1 DESCRIPTION

The Superglue package collects together support code for scripting
domain registration update clients. A Superglue object is built from
the following modules. See their documentation for full details; here
we mainly explain how they fit together.

=over

=item L<ReGPG::Login>

Used to read encrypted credentials. It provides a C<login> attribute
in Superglue objects that you use to access the registration update
interface.

=item L<Superglue::Contact>

=item L<Superglue::Delegation>

Used to represent the domain's registration details. You construct a
Superglue object with either or both of C<contact> and C<delegation>
attributes, representing the desired state of the domain's
registration. As a shorthand, the Superglue::Contact and
Superglue::Delegation methods are available on the Superglue object
itself.

You can also construct separate Superglue::Contact and
Superglue::Delegation objects to represent the current state of the
domain's registration, to compare with the desired state when working
out if a change is needed.

=item L<Superglue::Restful>

Optional support for JSON-over-HTTP interfaces that provides handy
C<GET> and C<POST> (etc.) methods on the Superglue object.

=item L<Superglue::WebDriver>

Optional support for scripting a website, as a last resort when a
domain registration service doesn't provide enough of an API.

=back

=cut

use strictures 2;
use warnings;

use Carp;
use Data::Compare;
use FindBin;
use Getopt::Long;
use IO::String;
use JSON;
use Moo;
use POSIX;
use Pod::Find;
use Pod::Usage;
use ReGPG::Login;
use Superglue::Contact;
use Superglue::Delegation;
use Sys::Syslog qw(:macros);
use Time::HiRes qw(gettimeofday);

use namespace::clean;

our @optional = qw(
	Superglue::Restful
	Superglue::WebDriver
);

# Mix in optional parts, before we try to grab their symbol tables.
with @optional;

# For exporting subroutines in script mode, and for extending command
# line options, we reach over into the symbol table to find the
# relevant variables in each module.
our %optional;
$optional{lc $_} = $Superglue::{$_.'::'}
    for map s{.*::}{}r, @optional;

=head1 SCRIPT MODE

As well as a conventional object-oriented interface, Superglue can
also be used in script mode by using it with the C<:script> import
tag. This has some radical effects:

=over

=item Implicit Superglue object

Rather than passing around a C<$sg> object and invoking methods on it,
you can call the methods like subroutines and they will use a hidden
global Superglue object.

=item Automatic command-line handling

The global Superglue object is constructed from the command line
automatically, using C<Superglue::getopt()>.

=back

=head2 Import tags

When your script needs optional features, add these tags when using
Superglue.

    use Superglue qw(:script);

=over

=item :script

Enable script mode.

=item :restful

Note that the script uses L<Superglue::Restful>. There aren't any
extra Restful command-line options.

=item :webdriver

Note that the script uses L<Superglue::WebDriver>, and handle the
extra WebDriver command-line options.

=back

=cut

our $script_self;

sub import {
	my $class = shift;
	my %tag; @tag{@_} = @_;
	my $script = delete $tag{':script'};
	# optional modules to enable
	my @module;
	# packages from which we export methods
	my @pkg = (
		\%Superglue::,
		\%Superglue::Contact::,
		\%Superglue::Delegation::,
	);
	for my $module (keys %optional) {
		next unless delete $tag{":$module"};
		push @pkg, $optional{$module};
		push @module, $module;
	}
	my @unknown = keys %tag;
	croak "unknown Superglue import tags @unknown" if @unknown;
	# export nothing unless we are in script mode
	return unless $script;
	# wrap exported methods with the implicit script self
	for my $pkg (@pkg) {
		my $methods = $pkg->{SUPERGLUE_EXPORT};
		for my $name (@$methods) {
			my $ref = $pkg->{$name};
			$main::{$name} = sub {
				return $script_self->$name(@_);
			};
		}
	}
	my $client = ($FindBin::Script =~ m{(?:^|/)superglue-([a-z0-9-]+)$})
	    ? $1 : undef;
	$script_self = Superglue::getopt($client, @module);
}

=head2 Command-line parser

The rough idea is that command-line options correspond to
attributes that you would pass to C<Superglue-E<gt>new()>.

The C<@module> list in the following subtroutines says which of the
optional features to include. (There is only one at the moment.)

=over

=item * Superglue::WebDriver

=back

=over

=item Superglue::usage(@module)

Print out short usage hints for the current script. The message is
extracted from the script's embedded POD (for its name and synopsis)
and from L<superglue(1)> for the description of the options including
any optional modules.

=cut

sub usage {
	my @sections = map "SYNOPSIS/(?i:$_) options", 'Superglue', @_;
	my $h = IO::String->new(my $out);
	pod2usage
	    -exit => 'NOEXIT',
	    -output => $h,
	    -verbose => 99,
	    -sections => 'NAME|SYNOPSIS';
	pod2usage
	    -exit => 'NOEXIT',
	    -input => "$FindBin::Dir/superglue",
	    -output => $h,
	    -verbose => 99,
	    -sections => [@sections];
	$out =~ s{\s*See superglue[^\n]*}{};
	print $out;
	exit 1;
}

=item Superglue::getopt($client, @module)

Parse C<@ARGV>, construct and return a Superglue object. If the
command line requires help, short usage messages are printed by
C<Superglue::usage>; long help messages (the script's embedded POD)
are printed using L<Pod::Usage>.

The C<$client> name is used to check consistency of the C<superglue>
field in the login credentials. It can be C<undef> to skip this check.

Each optional module can extend the command line options by defining a
C<@SUPERGLUE_GETOPT> variable containing a L<Getopt::Long>
specification, and attributes that correspond to those options.
The documentation for the extra options is in L<superglue(1)>.

=back

=cut

sub getopt {
	my $client = shift;
	my @opt = qw{
		contact|C=s
		debug|d
		delegation|D=s
		h|?
		help
		login|L=s
		not_really|not-really|n
		verbose|v
		zone|Z=s
	};
	for my $module (@_) {
		push @opt, @{ $optional{$module}->{SUPERGLUE_GETOPT} };
	}

	my %opt;
	Getopt::Long::Configure qw(posix_default gnu_getopt);
	GetOptions(\%opt, @opt) or exit 1;

	usage @_ if $opt{h};
	pod2usage -exit => 0, -verbose => 2 if $opt{help};

	# check that optional modules will work after construction
	$opt{$_} = 1 for @_;
	# for the login credentials safety check
	$opt{client} = $client if $client;

	my $sg = eval { Superglue->new(%opt) };
	return $sg if $sg;

	$@ =~ s{ at \S+ line [0-9.]+\s*$}{};
	print STDERR "$FindBin::Script: $@\n";
	exit 1;
}

=head1 ATTRIBUTES

The following options can be passed to Superglue's C<new> method. Many
of them also have accessor methods

=over

=item client => $name

(optional)

The client C<$name> must match the C<superglue> field in the login
credentials. This protects against exposing secrets to the wrong
registration provider.

=cut

has client => (
	is => 'ro',
    );

=item contact => $filename

(optional)

The C<$filename> is a YAML file containing the desired registration
contact details. See L<Superglue::Contact> for details of the file
format and the methods that the contact object handles.

=cut

has contact => (
	is => 'ro',
	predicate => 1,
	handles => [@Superglue::Contact::SUPERGLUE_EXPORT],
    );

=item debug => 1

Equivalent to C<verbosity =E<gt> LOG_DEBUG>

=item delegation => $filename

(optional)

The C<$filename> is a standard DNS zone file from which the zone's
desired delegation records are extracted. See L<Superglue::Delegation>
for details of the file format and the methods that the contact object
handles.

=cut

has new_delegation => (
	is => 'ro',
	handles => {
		'new_ds' => 'get_ds',
		'new_ns' => 'get_ns',
	},
    );

has old_delegation => (
	is => 'ro',
	handles => {
		'old_ds' => 'add_ds',
		'old_ns' => 'add_ns',
	},
	lazy => 1,
	default => sub {
		my $self = shift;
		$self->{old_delegation} =
		    Superglue::Delegation->new(zone => $self->{zone});
	},
    );

=item login => $filename

(required)

The C<$filename> is a YAML file containing login credentials with
encrypted secrets. See L<ReGPG::Login> for details of the file format,
and L<superglue(1)> for information about the C<superglue> field.

=cut

has login => (
	is => 'ro',
	required => 1,
	reader => 'regpg_login',
	handles => {
		'login_check' => 'check',
		'auth_basic' => 'auth_basic',
	    },
    );

=item not_really => $bool

Your script should use this attribute to enable check mode, so that it
does everything it can short of committing any changes.

=cut

has not_really => (
	is => 'rw',
	default => 0,
    );

=item verbose => 1

Equivalent to C<verbosity =E<gt> LOG_INFO>

=item verbosity => $level

(optional)

Set the verbosity to a L<Sys::Syslog> level.

=cut

has verbosity => (
	is => 'rw',
	default => LOG_NOTICE,
    );

=item zone => $domain_name

The zone whose registration details we will update if necessary.

=cut

has zone => (
	is => 'ro',
	required => 1,
    );

=back

=cut

around BUILDARGS => sub {
	my $orig = shift;
	my $class = shift;
	my %args = @_;

	# Contact, Delegation, Login objects are constructed
	# from their filenames.

	$args{contact} = Superglue::Contact->new($args{contact})
	    if exists $args{contact} and not ref $args{contact};

	# The zone name is required but this hasn't been checked yet;
	# if it's missing, just skip the delegation and fail later.

	my $delegation = delete $args{delegation};
	$args{new_delegation} = Superglue::Delegation->new(
		zone => $args{zone},
		file => $delegation,
	    ) if $delegation and $args{zone};

	$args{login} = ReGPG::Login->new(
		filename => $args{login},
	    ) if exists $args{login} and not ref $args{login};

	if ($args{client}) {
		my $yml = $args{login}{filename} // 'login';
		croak "$yml: expected field superglue: $args{client}"
		    unless defined $args{login}{superglue}
		    and $args{login}{superglue} eq $args{client};
	}

	# Convert boolean `verbose` and `debug` settings
	# into a `verbosity` level.

	$args{verbosity} = LOG_INFO
	    if delete $args{verbose};
	$args{verbosity} = LOG_DEBUG
	    if delete $args{debug};

	return $class->$orig(%args);
};

# nothing extra to do in constructor or destructor by default,
# but we need to provide a place for mixins to hook in

sub BUILD { }

sub DEMOLISH { }

=head1 METHODS

The methods described below are available as subroutines in
scripting mode.

Additional methods are provided by L<Superglue::Contact> and
L<Superglue::Delegation>. See the documentation for those modules for
details.

=cut

our @SUPERGLUE_EXPORT = qw(
	auth_basic
	debug
	debug_f
	delegation_matches
	error
	error_f
	has_contact
	login
	login_check
	old_delegation
	old_ds
	old_ns
	new_delegation
	new_ds
	new_ns
	not_really
	notice
	notice_f
	require_glueless
	verbose
	verbose_f
	warning
	warning_f
	zone
);

=head2 Delegations

=over

=item $sg->new_delegation

=item $sg->old_delegation

Superglue::Delegation objects representing the desired (new) state of
the delegation provided by the user, and the current (old) state of
the delegation as obtained from the registry.

=item $sg->new_ds

=item $sg->new_ns

Get the new delegation records that were provided on the command line
or when constructing the Superglue object. Equivalent to
C<$sg-E<gt>new_delegation-E<gt>get_ds> and
C<$sg-E<gt>new_delegation-E<gt>get_ns>.

=item $sg->old_ds

=item $sg->old_ns

Add old delegation records that have been read from the registr*
interface. Equivalent to C<$sg-E<gt>old_delegation-E<gt>add_ds> and
C<$sg-E<gt>old_delegation-E<gt>add_ns>.

=item $sg->require_glueless

Raise an error if the any of the new nameservers have glue.

=cut

sub require_glueless {
	my $self = shift;
	return unless $self->new_delegation;
	my $ns = $self->new_ns;
	for my $addr (values %$ns) {
		$self->error_f("glue is not allowed for this delegation")
		    if scalar keys %$addr;
	}
}

=item $sg->delegation_matches

In a scalar context, returns true if the old and new delegations are
the same.

In a list conext, returns a pair of booleans stating whether the NS
and DS RRsets match.

Prints informative messages in debug and verbose mode.

=cut

sub delegation_matches {
	my $self = shift;
	my %ret;
	for my $rr (qw(NS DS)) {
		my $get = "get_" . lc $rr;
		my $old = $self->old_delegation->$get();
		my $new = $self->new_delegation->$get();
		$ret{$rr} = Compare $old, $new;
		if ($ret{$rr}) {
			$self->verbose("$rr records match");
			$self->debug("current $rr records", $old);
			$self->debug("desired $rr records", $new);
		} else {
			$self->notice("$rr records differ");
			$self->verbose("current $rr records", $old);
			$self->verbose("desired $rr records", $new);
		}

	}
	return wantarray ? @ret{qw{NS DS}} : $ret{NS} && $ret{DS};
}

=back

=head2 Login credentials

=over

=item $sg->login

=item $sg->login($key)

Access the login credentials. Without arguments it returns the
L<ReGPG::Login> object. With an argument it is equivalent to
C<$sg-E<gt>login-E<gt>{$key}>.

=cut

sub login {
	my $login = shift->regpg_login;
	return @_ ? @$login{@_} : $login;
}

=item $sg->login_check(@fields)

Handled by ReGPG::Login->check

Unlike most methods, this one is renamed by Superglue to be less
ambiguous in this context.

=item $sg->auth_basic(@fields)

Handled by ReGPG::Login->auth_basic

=back

=head2 Logging

The logging methods use the L<ScriptDie> package to print messages
to C<STDERR> prefixed by the name of the script.

=over

=item $sg->log($message, @objects)

Print the C<$message> unconditionally. In debug mode it is decorated
with a timestamp, otherwise it is decorated with the script name. The
objects are pretty-printed as JSON, after the header line containing
the message.

=cut

sub log {
	my $self = shift;
	my $message = shift;
	my $zone = $self->zone;
	if ($self->{verbosity} < LOG_DEBUG) {
		print "$FindBin::Script ($zone): $message\n";
	} else {
		my ($seconds, $microseconds) = gettimeofday;
		my $stamp = strftime "%F %T", localtime $seconds;
		printf "%s.%03d %s\n", $stamp, $microseconds/1000, $message;
	}
	return unless @_;
	print to_json @_ > 1 ? [ @_ ] : $_[0],
	    { allow_nonref => 1, canonical => 1, pretty => 1 };
}

=item $sg->log_f($fmt, @args)

Print a message formatted using C<sprintf>

=cut

sub log_f {
	return shift->log(sprintf shift, @_);
}

=item $sg->debug($message, @json)

=item $sg->debug_f($message, @json)

Print the C<$message> if the verbosity is C<LOG_DEBUG>.

=cut

sub debug {
	my $self = shift;
	return $self->log(@_)
	    unless $self->{verbosity} < LOG_DEBUG;
}

sub debug_f {
	return shift->debug(sprintf shift, @_);
}

=item $sg->verbose($message)

=item $sg->verbose_f($message)

Print the C<$message> if the verbosity is C<LOG_INFO> or higher.

=cut

sub verbose {
	my $self = shift;
	return $self->log(@_)
	    unless $self->{verbosity} < LOG_INFO;
}

sub verbose_f {
	return shift->verbose(sprintf shift, @_);
}

=item $sg->notice($message)

=item $sg->notice_f($message)

Print the C<$message> if the verbosity is C<LOG_NOTICE> or higher.

=cut

sub notice {
	my $self = shift;
	return $self->log(@_)
	    unless $self->{verbosity} < LOG_NOTICE;
}

sub notice_f {
	return shift->notice(sprintf shift, @_);
}

=item $sg->warning($message)

=item $sg->warning_f($message)

Print the C<$message> if the verbosity is C<LOG_WARNING> or higher.

=cut

sub warning {
	my $self = shift;
	return $self->log(@_)
	    unless $self->{verbosity} < LOG_WARNING;
}

sub warning_f {
	return shift->warning(sprintf shift, @_);
}

=item $sg->error($message)

=item $sg->error_f($message)

Print the C<$message> and exits

=cut

sub error {
	shift->log(@_);
	exit 1;
}

sub error_f {
	return shift->error(sprintf shift, @_);
}

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
