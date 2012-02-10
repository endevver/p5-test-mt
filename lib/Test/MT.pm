package Test::MT;

=head1 NAME

Test::MT - MT-specific testing framework, subclass of Test::Builder

=head1 SYNOPSIS

   use Test::MT;

   # Brief but working code example(s) here showing the most common usage(s)
   # This section will be as far as many users bother reading, so make it as
   # educational and exemplary as possible.

=head1 DESCRIPTION

Test::MT is a subclass of Test::Builder::Module (and by extension, Exporter)
which provides MT-specific functions for testing the core application and its
plugins.

=cut

use strict;
use warnings;
use Carp;
use Data::Dumper;
use Test::Most;

our $VERSION = 1.0.0;

my $CLASS = __PACKAGE__;
use base qw( Test::Builder::Module );

our ( @EXPORT );

BEGIN {
    @EXPORT = (
        @Test::Most::EXPORT, 
        qw(
              is_object        out_like      err_like      tmpl_out_like
              are_objects      out_unlike    grab_stderr   tmpl_out_unlike
              get_last_output  get_tmpl_out  get_tmpl_error  
        )
    );
}


=head1 SUBROUTINES/METHODS

A separate section listing the public components of the module's interface.

These normally consist of either subroutines that may be exported, or methods
that may be called on objects belonging to the classes that the module
provides.

Name the section accordingly.

In an object-oriented module, this section should begin with a sentence (of the
form "An object of this class represents ...") to give the reader a high-level
context to help them understand the methods that are subsequently described.

METHODS:
    sub import
    sub _is_object
    sub are_objects
    sub err_like
    sub is_object
    sub out_like
    sub out_unlike
    sub tmpl_out_like
    sub tmpl_out_unlike

=cut


=head2 is_object

DOCUMENTATION NEEDED

=cut
sub is_object($$$) {
    my ( $got, $expected, $name ) = @_;
    my $tb = $CLASS->builder;
    $tb->diag( 'ARGYS '.scalar @_ );
    $tb->pass($name) if _is_object(@_);
    # return $builder->ok(@_);
    # $tb->_try( sub { $proto->can($method) } ) or push @nok, $method;
    # my( $rslt, $error ) = $tb->_try( sub { $object->isa($class) } );
    # $tb->diag( map "    $class->can('$_') failed\n", @nok );
}


=head2 are_objects

DOCUMENTATION NEEDED

=cut
sub are_objects($$$) {
    my ( $got, $expected, $name ) = @_;
    my $tb = $CLASS->builder;

    my $count = scalar @$expected;
    if ( $count != scalar @$got ) {
        $tb->fail($name);
        $tb->diag( '    got ', scalar(@$got), ' objects but expected ', $count );
        return;
    }

    for my $i ( 0 .. $count - 1 ) {
        return if !_is_object( $$got[$i], $$expected[$i], "$name (#$i)" );
    }
    $tb->pass($name);
}


my $out;

=head2 out_like

DOCUMENTATION NEEDED

=cut
sub out_like($$$$) {
    my ( $class, $params, $r, $name ) = @_;
    my $tb = $CLASS->builder;
    my $app = _run_app( $class, $params );
    $out = delete $app->{__test_output};
    return $tb->like( $out, $r, $name );
}


=head2 out_unlike

DOCUMENTATION NEEDED

=cut
sub out_unlike($$$$) {
    my ( $class, $params, $r, $name ) = @_;
    my $tb = $CLASS->builder;
    my $app = _run_app( $class, $params );
    $out = delete $app->{__test_output};
    return $tb->unlike( $out, $r, $name );
}


=head2 err_like

DOCUMENTATION NEEDED

=cut
sub err_like($$$$) {
    my ( $class, $params, $r, $name ) = @_;
    my $tb = $CLASS->builder;
    my $app;
    my $err = grab_stderr( sub { $app = _run_app( $class, $params ) } );
    print "OUTPUT = " . $app->{__test_output} . "\n" if ( !$err );
    return $tb->like( $err, $r, $name );
}

my ($tmpl_out, $tmpl_err);

=head2 _tmpl_out

DOCUMENTATION NEEDED

=cut
sub _tmpl_out($$$) {
    my ( $text, $param, $ctx_h ) = @_;
    my $tb = $CLASS->builder;

    require MT::Object;
    MT::Object->driver->clear_cache;

    require MT::Request;
    MT::Request->instance->reset;

    require MT::Template;
    my $tmpl = MT::Template->new;
    $tmpl->blog_id( $ctx_h->{blog_id} ) if ( $ctx_h->{blog_id} );
    $tmpl->text($text);

    require MT::Template::Context;
    my $ctx = MT::Template::Context->new;
    while ( my ( $k, $v ) = each %$ctx_h ) {
        $ctx->stash( $k, $v );
    }

    $tmpl->context($ctx);
    $tmpl->param($param);
    $tmpl_out = $tmpl->output;
    $tmpl_err = $tmpl->errstr;
    return $tmpl_out;
}


=head2 tmpl_out_like

DOCUMENTATION NEEDED

=cut
sub tmpl_out_like($$$$$) {
    my ( $text, $param, $ctx_h, $re, $name ) = @_;
    my $tb = $CLASS->builder;

    return $tb->like( _tmpl_out( $text, $param, $ctx_h ), $re, $name );
}


=head2 tmpl_out_unlike

DOCUMENTATION NEEDED

=cut
sub tmpl_out_unlike($$$$$) {
    my ( $text, $param, $ctx_h, $re, $name ) = @_;
    my $tb = $CLASS->builder;

    return $tb->unlike( _tmpl_out( $text, $param, $ctx_h ), $re, $name );
}


=head2 grab_stderr

DOCUMENTATION NEEDED

=cut
sub grab_stderr(\&) {
    my ($code) = @_;
    my $tb = $CLASS->builder;
    my $out;
    local *SAVEERR;
    open SAVEERR, ">&STDERR";
    close STDERR;
    open STDERR, ">", \$out;

    $code->();

    close STDERR;
    open STDERR, ">&SAVEERR";

    return $out;
}

=head2 _is_object

DOCUMENTATION NEEDED

=cut
sub _is_object {
    my ( $got, $expected, $name ) = @_;
    my $tb = $CLASS->builder;

    if ( !defined $got ) {
        $tb->fail($name);
        $tb->diag('    got undef, not an object');
        return;
    }

    if ( !$got->isa( ref $expected ) ) {
        $tb->fail($name);
        $tb->diag( '    got a ', ref($got), ' but expected a ', ref $expected );
        return;
    }

    if ( $got == $expected ) {
        $tb->fail($name);
        $tb->diag(
'    got the exact same instance as expected, when really expected a different but equivalent object'
        );
        return;
    }

    # Ignore object columns that have undefined values.
    my ( %got_values, %expected_values );
    while ( my ( $field, $value ) = each %{ $got->{column_values} } ) {
        $got_values{$field} = $value if defined $value;
    }
    while ( my ( $field, $value ) = each %{ $expected->{column_values} } ) {
        $expected_values{$field} = $value if defined $value;
    }

    if ( ! $tb->eq_deeply( \%got_values, \%expected_values ) ) {

        # 'Test' again so the helpful failure diagnostics are output.
        $tb->is_deeply( \%got_values, \%expected_values, $name );
        return;
    }

    return 1;
}


=head2 get_last_output

DOCUMENTATION NEEDED

=cut
sub get_last_output { return "$out"; }


=head2 get_tmpl_out

DOCUMENTATION NEEDED

=cut
sub get_tmpl_out   { return "$tmpl_out" }


=head2 get_tmpl_error

DOCUMENTATION NEEDED

=cut
sub get_tmpl_error { return "$tmpl_err" }





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
