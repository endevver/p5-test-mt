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

use 5.010_001;
use strict;
use warnings;
use FindBin                 qw($Bin);
use Try::Tiny               ();
use Carp                    ();
use Scalar::Util            ();
use Test::MT::Util          ();
use Class::Load             qw( load_class );
use Package::Stash;
use autodie;
use Data::Printer           ();
use Test::Most;
use Test::Builder;
use Test::MT;
use Test::MT::ConfigMgr;

our ( @ISA, @EXPORT, $CLASS );

use parent qw( Test::Builder::Module );

# our @ISA = qw( Test::Builder::Module );
# use Exporter qw( import );

BEGIN {
    # @ISA    ||= qw(Test::Builder::Module);
    $CLASS  = __PACKAGE__;
    @EXPORT = (
        @Test::Most::EXPORT, 
        @Test::MT::EXPORT,
        qw(
            construct_default
            load_class
            p
        ),
    );
}


sub new {
    my $proto = shift;
    $proto    = ref $proto || $proto;
    my $self  = bless { @_ }, $proto;
}

=pod

All arguments passed to import() are passed onto Your::Module->builder->plan()
with the exception of import =>[qw(things to import)].

    use Your::Module import => [qw(this that)], tests => 23;

says to import the functions this() and that() as well as set the plan to be
23 tests.

import() also sets the exported_to() attribute of your builder to be the
caller of the import() function.

Additional behaviors can be added to your import() method by overriding
import_extra().


=cut
sub import_extra {
    my $class   = $_[0];
    my $caller  = caller;
    my $test    = $class->builder;
    my $package = $test->caller;
    {
        no strict 'refs';
        unshift( @{$package."::ISA"}, $class )
            unless $class ~~ @{$package."::ISA"};
    }
    # Default pragmas for all tests
    strict->import;
    warnings->import;
    feature->import(':5.10');   # use feature qw(switch say state)
    # mro->import('c3');          # enable C3 MRO for this class
    # mro::set_mro( $package, 'c3' );
    Carp->import(qw( carp croak confess cluck ));
    Test::Most->import;
    Test::More->import;
    Scalar::Util->import(qw( blessed looks_like_number ));
    Data::Printer->import({
        return_value => 'pass'
    });

    $test->exported_to($package);
    # my( @imports ) = $class->_strip_imports( \@_ );

    if ( 'tests' ~~ @_  ) {
        $test->plan( @_ ) unless $test->has_plan;
    }
    else {
        #Z
        # $test->no_plan
    }

    $class->export_to_level( 2, $class, @EXPORT );
}

sub construct_default {
    my $pkg  = shift || scalar caller;
    my $test = $pkg->new;

    require Test::MT::Environment;
    my $env = Test::MT::Environment->new()
        or die "Could not create \$test->env";

    $test->env( $env );
    $env->init()    or Carp::confess "Init error: "   . $env->errstr;
    # $env->init_db() or Carp::confess "Init DB error: ". $env->errstr;

    my $app      = $test->init_app( TestDatabase =>  $env->db_file )
        or die "No MT object " . MT->errstr;
    $test->app( $app );

    my $data     = $env->init_data( file => './data/bootstrap_env.yaml' )
        or die "Error creating test data: ".$env->errstr;

    my $env_data = $data->install()
        or die "Could not create \$env_data";

    $env->init_upgrade()
        or die "Could not upgrade DB";

    die 'Cannot app' unless $test->can('app');
    $test;
}


sub init { shift }


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


sub env {
    my $self = shift;
    return @_ ? $self->{env} = shift : $self->{env};
}


sub app {
    my $self = shift;
    return @_ ? $self->{app} = shift : $self->{app};
}


sub test_basename {
    my $self = shift;
    (split("::", ( ref $self || $self )))[1];
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

