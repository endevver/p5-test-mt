package Test::MT::Suite::Compile;

=head1 NAME

Test::MT::Suite::Compile

=head1 DESCRIPTION

Tests for successful compilation of all classes in the distribution

=cut

use 5.008_009;
use strict;
use warnings;
use Test::More;
use Try::Tiny;
use Test::Trap qw( trap $trap :stdout(systemsafe)
                  :flow :warn :stderr(systemsafe) );

usemods( 
    'Test::MT',                # Test::Builder::Module subclass
    'Test::MT::Base',          # Abstract base class for test object classes
    'MT::App::Test',           # MT::App subclass suited for testing
    'Test::MT::Environment',   # Config object for testing environment
    'Test::MT::Data',          # Abstract base class for test data classes
    'Test::MT::Data::Perl',    # Perl-based data class
    'Test::MT::Data::YAML',    # YAML-based data class
    'Test::MT::Util'           # Various utilities
);

done_testing();

sub usemods { use_ok( $_ ) for @_ }


1;

__END__

# my $ok;
# END { BAIL_OUT "Could not load all modules" unless $ok }
# ok 1, 'All modules loaded successfully';
# $ok = 1;
