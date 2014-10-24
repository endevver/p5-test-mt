package Test::MT::ConfigMgr;

=head1 NAME

Test::MT::ConfigMgr

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

use strict;
use warnings;
# use feature qw( state say );
use parent 'MT::ConfigMgr';

# ALL YOUR CONFIG ARE BELONG TO US!
#   The following line enables this class to inject itself into MT's
# config model and be the singleton MT::Config instance.  This is useful in
# many, many ways...
$MT::ConfigMgr::cfg = __PACKAGE__->new;

# Static variable holding our per-process Database config
my $Database;

sub read_config_file {
    my $class = shift;

    # Let MT::ConfigMgr do what it normally does in reading the config
    $class->SUPER::read_config_file(@_);

    # Now, we get the singleton instance which, thanks to like 15 above
    # is an object of THIS CLASS.
    my $mgr   = $class->instance;
    my $file_val = $mgr->get('Database');

    unless ( $Database ) {
        # We alter the Database value to insert the process ID
        # thus giving each process its own database.  This allows us
        # to run our test suite in parallel!
        ( $Database = $file_val ) =~ s{mt.db$}{mt-$$.db};
    }

    if ( ($Database||$file_val) ne $file_val ) {
        $mgr->set( 'Database', $Database );
        print STDERR
              __PACKAGE__
            . ": Database config value updated from $file_val to $Database\n"
            if $mgr->get('DebugMode');
    }
}

1;