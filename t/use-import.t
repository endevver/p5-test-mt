#!perl

use Test::Most;
{
    package Test::MT::Suite::UseImport;
    ::use_ok('Test::MT::Base');
    ::is( (grep { /^Test::MT::Base$/ } @Test::MT::Suite::UseImport::ISA), 1, 'Test::MT::Base is parent' );

    ::note "Testing class methods...";
    ::is( ref __PACKAGE__->can($_), 'CODE', "...can $_()" )
        for qw( new construct_default env app init finish init_app init_cms builder );

    ::note "Testing imported functions...";
    ::isnt( defined( &{__PACKAGE__."::$_" }), undef, "...can also $_")
        for @Test::Most::EXPORT,
            qw(
                
                is_object        out_like      err_like      tmpl_out_like
                are_objects      out_unlike    grab_stderr   tmpl_out_unlike
                get_last_output  get_tmpl_out  get_tmpl_error
                get_test_builder
            );
}

done_testing();

