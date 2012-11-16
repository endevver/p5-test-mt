package Test::MT::Base;

=head1 NAME

Test::MT::Base - Abstract base class for all MT tests

=head1 SYNOPSIS

   use Test::MT::Base;

   # Brief but working code example(s) here showing the most common usage(s)
   # This section will be as far as many users bother reading, so make it as
   # educational and exemplary as possible.

=head1 DESCRIPTION

A full description of the module and its features.

May include numerous subsections (i.e., =head2, =head3, etc.).

=cut

##########################################################################

use strict;
use warnings;
use autodie;
use Carp                qw( croak confess carp );
use Test::Builder::Module ();
use Test::Builder;
use Test::Most;
use Test::MT;
use Try::Tiny           ();
use Test::MT::Util      ();
use FindBin             qw( $Bin );
use parent qw( Test::Builder::Module );

our ( $CLASS, @EXPORT );
our $session_id;
our $session_username = '';

BEGIN {
    $CLASS  = __PACKAGE__;
    @EXPORT = (
        @Test::More::EXPORT, 
        @Test::Most::EXPORT, 
        @Test::MT::EXPORT, 
    );
}



sub new {
    my $proto = shift;
    $proto = ref $proto || $proto;
    my $self = bless {}, $proto;
}



sub import {
    my $pkg    = $_[0];
    my $caller = caller;

    # Don't run all this when loading ourself.
    return 1 if $pkg eq 'Test::Builder::Module';

    {
        no strict 'refs';
        unshift( @{$caller."::ISA"}, $pkg )
            unless $pkg ~~ @{$caller."::ISA"};
    }

    # Default pragmas for all tests
    strict->import;
    warnings->import;
    feature->import(':5.10');   # use feature qw(switch say state)
    Class::Load->import(':all');
    Carp->import(qw( carp croak confess cluck ));
    Test::Most->import;

    goto &Test::Builder::Module::import;
}

sub construct_default {
    my $pkg = shift;

    my $test = $pkg->new();
    require Test::MT::Environment;
    my $env = Test::MT::Environment->new()
        or die "Could not create \$test->env";
    $test->env( $env );

    $env->db_file or die "No Database file value for config to use";

    $env->init()    or confess "Init error: "   . $env->errstr;
    $env->init_db() or confess "Init DB error: ". $env->errstr;

    my $app = $test->init_app( TestDatabase =>  $env->db_file )
        or die "No MT object " . MT->errstr;
    $test->app( $app );


    my $data = $env->init_data( file => './data/bootstrap_env.yaml' )
                   or die "Error creating test data: ".$env->errstr;

    my $env_data = $data->install()
        or die "Could not create \$env_data";

    $env->init_upgrade()
        or die "Could not upgrade DB";

    die 'Cannot app' unless $test->can('app');
    $test;
}



sub env {
    my $self = shift;
    return @_ ? $self->{env} = shift : $self->{env};
}



sub app {
    my $self = shift;
    return @_ ? $self->{app} = shift : $self->{app};
}



sub init { shift }



sub test_basename {
    my $self = shift;
    (split("::", ( ref $self || $self )))[1];
}



sub init_app {
    my $pkg  = shift;
    my %args = @_;
    my $env  = $pkg->env;
    
    my $app_class = $env->app_class;
    my $app       = $app_class->construct(
        Config => $env->config_file,
        App    => $app_class,
             %args
    )
        or die "No MT object " . MT->errstr;

    MT->set_instance( $app );

    return $app;
}



sub init_cms {
    my $pkg = shift;
    my ($cfg) = @_;

    require MT::App::CMS;
    MT::App::CMS->instance( $cfg ? ( Config => $cfg ) : () );
}



sub finish { shift }


BEGIN {
    my $mt = $ENV{MT_HOME}
        or die "Please set your MT_HOME environment variable";
    $mt =~ s{/*$}{/}x;      # Force trailing slash
    $ENV{MT_HOME} = $mt;

}


# addlibs was taken out of a BEGIN block and enclosed as a subroutine
# Not sure that it's needed and it may actually make things more difficult
# by overly including paths into @INC, masking issues...
sub addlibs {
    my $mt = $ENV{MT_HOME};
    my @test_libs = (
        "${mt}lib",     "${mt}extlib",      # MT core library
        "${mt}t/lib",   "${mt}t/extlib",    # MT test library
    );

    $Bin =~ s{/*$}{/}i;
    if ( $Bin ne $mt ) { # We may be running a plugin's test
        unshift( @test_libs, (
            "${Bin}../lib",  "${Bin}../extlib",    # Plugin's core library
            "${Bin}lib",     "${Bin}extlib"        # Plugin's test library
        ));
    }
    unshift( @INC, ( grep {-d $_ } @test_libs ));
    
}


1;

__END__

