package Pure::Test::MT::Data;

use strict;
use warnings;

use base qw( Class::Accessor::Fast );

__PACKAGE__->mk_accessors(qw( data env_data ));

package Test::MT::Data;

=head1 NAME

Test::MT::Data - Abstract base class for all test data classes

=head1 SYNOPSIS

    package Test::MT::Data::FiddleFaddle;

    use base qw( Test::MT::Data );

    sub init    { ... }
    sub install { ... }

=head1 DESCRIPTION

Abstract base class for all test data classes

=cut

use strict;
use warnings;
use Carp;
use Data::Dumper;

use base qw( Pure::Test::MT::Data
             Class::Data::Inheritable
             MT::ErrorHandler );

( my $key = lc(__PACKAGE__) ) =~ s{:+}{-}g;
__PACKAGE__->mk_classdata( Key => $key );

=head1 SUBROUTINES/METHODS

A separate section listing the public components of the module's interface.

These normally consist of either subroutines that may be exported, or methods
that may be called on objects belonging to the classes that the module
provides.

Name the section accordingly.

In an object-oriented module, this section should begin with a sentence (of the
form "An object of this class represents ...") to give the reader a high-level
context to help them understand the methods that are subsequently described.

=cut

sub is_mt_v5 { substr( MT->product_version, 0, 1 ) == 5 }

sub init;

sub install;

1;
__END__

=head1 DIAGNOSTICS

A list of every error and warning message that the module can generate (even
the ones that will "never happen"), with a full explanation of each problem,
one or more likely causes, and any suggested remedies.

=head1 BUGS AND LIMITATIONS

There are no known bugs in this module.

Please report problems via http://help.endevver.com/

Patches are welcome.

=head1 AUTHOR

Jay Allen, Endevver, LLC http://endevver.com/

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2012 Endevver, LLC (info@endevver.com).
All rights reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself. See L<perlartistic>.  This program is
distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.
