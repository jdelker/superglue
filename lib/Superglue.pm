package Superglue;

use strictures 2;
use strict;

use Carp;
use Getopt::Long;
use Pod::Usage;
use ReGPG::Login;
use ScriptDie;
use Superglue::Contact;
use Superglue::Delegation;

our @EXPORT_SUPERGLUE = qw(
);

our $script_self;

sub import {
	my $class = shift;
	my %opt; @opt{@_} = @_;
	my $script = delete $opt{':script'};
	my $restful = delete $opt{':restful'};
	my $webdriver = delete $opt{':webdriver'};
	my @opt = keys %opt;
	croak "unknown Superglue options @opt" if @opt;
	# export nothing unless we are in script mode
	return unless $script;
	# packages from which we export methods
	my @pkg = (
		\%Superglue::,
		\%Superglue::Contact::,
		\%Superglue::Delegation::,
	);
	push @pkg, \%Superglue::Restful:: if $restful;
	push @pkg, \%Superglue::WebDriver:: if $webdriver;
	# wrap exported methods with the implicit script self
	for my $pkg (@pkg) {
		my $methods = $pkg->{EXPORT_SUPERGLUE};
		for my $name (@$methods) {
			my $ref = $pkg->{$name};
			$main::{$name} = sub {
				# like return $script_self->$name(@_)
				unshift @_, $script_self;
				goto &$ref;
			};
		}
	}
}

1;
