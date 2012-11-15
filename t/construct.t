#!perl

use Test::Most;
{
    package Test::MT::Suite::Construct;
    use Test::MT::Base;

    my $test = __PACKAGE__->construct_default();

    ::isa_ok( $test, $_, '$test' )
        for __PACKAGE__, qw( Test::MT::Base Test::Builder::Module );

    ::isnt( $test->app, undef, 'test->app is defined' );
    ::isa_ok( $test->app, $_, '$test->app' )
        for qw( MT::App::Test MT::App MT );

    ::isnt( $test->env, undef, 'test->env is defined' );
    ::isa_ok( $test->env, $_, '$test->env' )
        for qw( Test::MT::Environment );
    ::explain $test->env;

    ::isnt( $test->env->data, undef, 'test->env->data is defined' );
    ::isa_ok( $test->env->data, $_,  '$test->env->data')
        for qw( Test::MT::Data::YAML );

    ::isnt( $test->env->data->env_data, undef, 'test->env->data->env_data is defined' );
    ::is( ref $test->env->data->env_data, 'HASH', '$test->env->data->env_data isa HASH' );
}

done_testing();

