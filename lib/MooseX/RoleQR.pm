package MooseX::RoleQR;

use 5.010;
use strict;
use warnings;
use utf8;

BEGIN {
	$MooseX::RoleQR::AUTHORITY = 'cpan:TOBYINK';
	$MooseX::RoleQR::VERSION   = '0.001';
}

use Moose ();
use Moose::Exporter;
use Scalar::Does -constants;

Moose::Exporter->setup_import_methods(
	with_meta => [qw/ before after around /],
	also      => 'Moose::Role',
);

my %ROLE_METAROLES = (
	role                       => ['MooseX::RoleQR::Trait::Role'],
	application_to_class       => ['MooseX::RoleQR::Trait::Application::ToClass'],
	application_to_role        => ['MooseX::RoleQR::Trait::Application::ToRole'],
);

sub _add_method_modifier
{
	my $type = shift;
	my $meta = shift;

	if (does($_[0], REGEXP))
	{
		my $pusher = "add_deferred_${type}_method_modifier";
		return $meta->$pusher(@_);
	}

	Moose::Util::add_method_modifier($meta, $type, \@_);
}

sub before { _add_method_modifier(before => @_) }
sub after  { _add_method_modifier(after  => @_) }
sub around { _add_method_modifier(around => @_) }

sub init_meta
{
	my $class   = shift;
	my %options = @_;
	Moose::Role->init_meta(%options);

	Moose::Util::MetaRole::apply_metaroles(
		for            => $options{for_class},
		role_metaroles => \%ROLE_METAROLES,
	);
}

BEGIN {
	package MooseX::RoleQR::Meta::DeferredModifier;
	no thanks;
	use Moose;
	use Scalar::Does -constants;
	use namespace::sweep;
	
	has [qw/ expression body /] => (is => 'ro', required => 1);
	
	sub matches_name
	{
		my ($meta, $name) = @_;
		my $expr = $meta->expression;
		return $name =~ $expr if does($expr, REGEXP);
		return $expr->($name) if does($expr, CODE);
		return;
	}
};

BEGIN {
	package MooseX::RoleQR::Trait::Role;
	no thanks;
	use Moose::Role;
	use Scalar::Does -constants;
	use Carp;
	use namespace::sweep;
	
	has deferred_modifier_class => (
		is      => 'ro',
		isa     => 'ClassName',
		default => sub { 'MooseX::RoleQR::Meta::DeferredModifier' },
	);
	
	for my $type (qw( after around before override ))
	{
		no strict 'refs';
		my $attr = "deferred_${type}_method_modifiers";
		has $attr => (
			traits  => ['Array'],
			is      => 'ro',
			isa     => 'ArrayRef[MooseX::RoleQR::Meta::DeferredModifier]',
			default => sub { +[] },
			handles => {
				"has_deferred_${type}_method_modifiers" => "count",
			},
		);
		
		my $pusher = "add_deferred_${type}_method_modifier";
		*$pusher = sub {
			my ($meta, $expression, $body) = @_;
			my $modifier = does($expression, 'MooseX::RoleQR::Meta::DeferredModifier')
				? $expression
				: $meta->deferred_modifier_class->new(expression => $expression, body => $body);
			push @{ $meta->$attr }, $modifier;
		};
		
		around "add_${type}_method_modifier" => sub {
			my ($orig, $meta, $expression, $body) = @_;
			if (does($expression, 'MooseX::RoleQR::Meta::DeferredModifier')
			or  does($expression, REGEXP))
				{ return $meta->$pusher($expression, $body) }
			else
				{ return $meta->$orig($expression, $body) }
		};
		
		next if $type eq 'override';
		*{"get_deferred_${type}_method_modifiers"} = sub {
			my ($meta, $name) = @_;
			grep { $_->matches_name($name) } @{ $meta->$attr };
		};
	}
	
	sub get_deferred_override_method_modifier
	{
		my ($meta, $name) = @_;
		my @r = grep { $_->matches_name($name) } @{ $meta->deferred_override_method_modifiers };
		carp sprintf(
			"%s has multiple override modifiers for method %s",
			$meta->name,
			$name,
		) if @r > 1;
		return $r[0];
	}
};

BEGIN {
	package MooseX::RoleQR::Trait::Application::ToClass;
	no thanks;
	use Moose::Role;
	use namespace::sweep;
	
	after apply_override_method_modifiers => sub {
		my ($self, $role, $class) = @_;
		return unless $role->can('get_deferred_override_method_modifier');
		for my $method ( $class->get_all_method_names )
		{
			next if $role->get_override_method_modifier($method);
			my $modifier = $role->get_deferred_override_method_modifier($method)
				or next;
			$class->add_override_method_modifier($method, $modifier->body);
		}
	};
	
	after apply_method_modifiers => sub {
		my ($self, $modifier_type, $role, $class) = @_;
		my $add = "add_${modifier_type}_method_modifier";
		my $get = "get_deferred_${modifier_type}_method_modifiers";
		return unless $role->can($get);
		for my $method ( $class->get_all_method_names )
		{
			$class->$add($method, $_->body) for $role->$get($method);
		}
	};
};

BEGIN {
	package MooseX::RoleQR::Trait::Application::ToRole;
	no thanks;
	use Moose::Role;
	use namespace::sweep;

	before apply => sub {
		my ($self, $role1, $role2) = @_;
		Moose::Util::MetaRole::apply_metaroles(
			for            => $role2,
			role_metaroles => \%ROLE_METAROLES,
		);
	};

	after apply_override_method_modifiers => sub {
		my ($self, $role1, $role2) = @_;
		my $add = "add_overide_method_modifier";
		my $get = "deferred_override_method_modifiers";
		$role2->$add($_) for @{ $role1->$get };
	};
	
	after apply_method_modifiers => sub {
		my ($self, $modifier_type, $role1, $role2) = @_;
		my $add = "add_${modifier_type}_method_modifier";
		my $get = "deferred_${modifier_type}_method_modifiers";
		$role2->$add($_) for @{ $role1->$get };
	};
};

1;

__END__

=head1 NAME

MooseX::RoleQR - allow "before qr{...} => sub {...};" in roles

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=MooseX-RoleQR>.

=head1 SEE ALSO

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2012 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.


=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

