package Test::MT::Base;

=head1 NAME

Test::MT::Base - Abstract base class for all MT tests

=cut

##########################################################################

use 5.010_001;
use strict;
use warnings;
use Try::Tiny;
use FindBin                 qw($Bin);
use Carp                    ();
use Scalar::Util            ();
use Test::MT::Util          ();
use Class::Load             qw( load_class );
use Package::Stash;
use autodie;
use Test::Most;
use Test::Builder;
use Test::MT;
use Test::MT::ConfigMgr;
use Data::Printer;

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

    my $env = try {
        require Test::MT::Environment;
        my $e = Test::MT::Environment->new->init();
        $e->db_file or die "env->db_file undefined";
        $e;
    }
    catch { Carp::confess( "Error initializing test environment: $_" ) };
    $test->env( $env );
    # use Data::Dumper; print Dumper( $env );

    my $app
        =  try { $test->init_app( TestDatabase =>  $env->db_file ) }
         catch { Carp::confess( "Error initializing test app: $_" ) };
    $test->app( $app );
    # use Data::Dumper; print Dumper( $app );

    try   { $env->init_upgrade() }
    catch { Carp::confess("Could not upgrade DB") };

    my $data
        =  try { $env->init_data( file => './data/bootstrap_env.yaml' ) }
         catch { Carp::confess( "Error initializing test data: $_" ) };
    # use Data::Dumper; print Dumper( $data );

    my $env_data
        =  try { $data->install(); }
         catch { Carp::confess( "Could not create \$env_data: $_" ) };
    # use Data::Dumper; print Dumper( $env_data );

    try   { $env->init_upgrade() }
    catch { Carp::confess("Could not upgrade DB") };

    Carp::confess('Cannot app') unless $test->can('app');
    $test;
}


sub init { shift }


sub init_app {
    my $self      = shift;
    my %args      = @_;
    my $env       = $self->env
        or Carp::confess('init_app called with no test environment');
    my $app_class = $env->app_class;

    %args = (
        Config => $env->config_file,
        App    => $app_class,
        %args
    );

    if ( my $app = $app_class->construct( %args ) ) {
        MT->set_instance( $app );
        return $app;
    }

    my $error  = '';
    my $mterr  = MT->errstr // '';
    $error    .= "MT error: $mterr\n" unless $mterr eq '';
    $error    .= 'MT initialization arguments: '
               . Data::Dumper::Dumper(\%args);
    die $error;
}


sub init_cms {
    my $pkg = shift;
    my ($cfg) = @_;

    require MT::App::CMS;
    MT::App::CMS->instance( $cfg ? ( Config => $cfg ) : () );
}


sub env {
    my $self     = shift;
    $self->{env} = shift if @_;
    $self->{env};
}

sub app {
    my $self     = shift;
    $self->{app} = shift if @_;
    $self->{app};
}

sub plugin {
    my $self      = shift;
    my $plugin_id = shift;
    my ( $plugin ) = MT->component($plugin_id)
                  || MT::Plugin->select($plugin_id);
    die "Could not find plugin $plugin"
        unless $plugin;
    $plugin;
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

1;

__END__

=head1 SYNOPSIS

   use Test::MT::Base;

=cut
