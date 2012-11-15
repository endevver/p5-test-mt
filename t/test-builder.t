#!perl

use Test::Most;
{
    package Test::MT::Suite::TestBuilder;
    use Test::MT::Base;

    my $t  = ::new_ok(__PACKAGE__);
    my $tb = $t->builder;
    ::isa_ok( $tb, 'Test::Builder' );
}

done_testing();

