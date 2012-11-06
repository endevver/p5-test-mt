package Test::MT::Util;

use strict;
use warnings;
use Scalar::Util qw( blessed );
use base 'Exporter';
our @EXPORT_OK = qw( debug_handle DEBUG_ON );

sub DEBUG_ON { 1 }

# Ways this method/function can be called
#   1. my $debug = $self->debug_handler();         obj, undef
#   2. $self->debug_handler( sub { } );            obj, CODE
#   3. debug_handler();                            undef, undef
#   4. debug_handler( sub { } );                   CODE undef
sub debug_handle {
    my $self = shift;
    my $hdlr = shift;
    my $pkg  = blessed $self;

    unless ( $pkg ) {
        $hdlr = $self;              # May be undef, see #3 above
        $pkg = caller;
    }

    return sub {} unless eval { $pkg->DEBUG_ALL } || eval { $pkg->DEBUG };

    return $hdlr ?  sub { $hdlr->(@_) }
                 :  sub { print STDERR join("\n",@_)."\n" };
}

1;