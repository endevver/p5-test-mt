package Pure::Test::MT::Environment;

use base qw( Class::Accessor );

__PACKAGE__->mk_accessors(qw(
    mt_dir  test_dir  config_dir  config_file  ds_dir  ref_dir db_file
    data
));

#########################################################################
package Test::MT::Environment;

=head1 NAME

Test::MT::Environment - Class representing the environment for all MT tests

=head1 SYNOPSIS

    use Test::MT::Environment;
    my $env = Test::MT::Environment->new();
    $env->init();

=head1 DESCRIPTION

Class representing the environment under which all all MT tests are executing

=cut

use strict;
use warnings;
use Carp qw( cluck );
use Data::Dumper;
use File::Spec;
use File::Basename  qw( dirname basename );
use File::Path      qw( make_path remove_tree );
use Cwd             qw( getcwd );
use File::Copy      qw( cp );

use base qw( Pure::Test::MT::Environment
             Class::Data::Inheritable
             MT::ErrorHandler );

__PACKAGE__->mk_classdata( %$_ )
    for (
            { DBFile        => 'mt.db'                               },
            { ConfigFile    => 'test.cfg'                            },
            { DatabaseClass => join('::', __PACKAGE__, 'Database')   },
            { DataClass     => do {
                                    (my $p = __PACKAGE__) =~ s{Environment}{Data::YAML};
                                    $p;
                                },
            }
        );

=head1 SUBROUTINES/METHODS

A separate section listing the public components of the module's interface.

These normally consist of either subroutines that may be exported, or methods
that may be called on objects belonging to the classes that the module
provides.

Name the section accordingly.

In an object-oriented module, this section should begin with a sentence (of the
form "An object of this class represents ...") to give the reader a high-level
context to help them understand the methods that are subsequently described.

=head2 init

This method initializes the path-related variables necessary to run MT and
locate our own modules.

=cut
sub init {
    my $self = shift;
    $self->init_paths() or return;
    $self;
}

sub progress { }

sub error {
    my $self = shift;
    cluck join( '. ', $@ );
    $self->SUPER::error(@_);
}


=head2 init_paths

This method initializes the path-related variables necessary to run MT and
locate our own modules.  These include the following environment variables
shown with their corresponding accessor methods.  For more details, refer
each accessor method's POD documentation.

=over4

=item * $ENV{MT_HOME} = $self->mt_dir()

MT home directory

=item * $ENV{MT_TEST_DIR} = $self->test_dir()

Root directory containing tests

=item * $ENV{MT_CONFIG} = $self->config_file()

The file which contains MT config information

=item * $ENV{MT_DS_DIR} = $self->ds_dir()

The directory containing our working test Database (if using SQLite)

=item * $ENV{MT_REF_DIR} = $self->ref_dir()

The directory containing our pristine test Database (if using SQLite)

=back

=cut
sub init_paths {
    my $self = shift;

    return unless $ENV{MT_HOME}     = $self->mt_dir()
              and $ENV{MT_TEST_DIR} = $self->test_dir()
              and $ENV{MT_CONFIG}   = $self->config_file()
              and $ENV{MT_DS_DIR}   = $self->ds_dir()
              and $ENV{MT_REF_DIR}  = $self->ref_dir();
              
    # foreach my $path (qw( ds_dir ref_dir )) {
    #     $self->{$path}
    #         = File::Spec->rel2abs( $self->$path, $self->config_dir )
    #             or return $self->error("Could not set path for $path: "
    #                                     .$self->errstr );
    # }

    1;
}



=head2 mt_dir

=item * $ENV{MT_HOME} = $self->mt_dir()

MT home directory

=cut
sub mt_dir {
    my $self = shift;
    return $self->SUPER::mt_dir() if $self->SUPER::mt_dir;
    return $self->SUPER::mt_dir(@_) if @_;

    my $dir = $ENV{MT_HOME}
          ||= do {
                    my @pieces = File::Spec->splitdir( getcwd() );
                    pop @pieces unless -e 'mt.cgi';
                    File::Spec->catdir( @pieces );
                 };

    $dir = File::Spec->rel2abs( $dir, getcwd() );

    $dir
        or return $self->error('Could not determine MT_HOME directory');

    -d $dir
        or return $self->error('Bad MT_HOME directory: '. $ENV{MT_HOME} );

    chdir $dir or die "Can't cd to MT_HOME directory, $dir: $!\n";

    return $self->mt_dir( $ENV{MT_HOME} = $dir );
}


=head2 test_dir

=item * $ENV{MT_TEST_DIR} = $self->test_dir()

Root directory containing tests

=cut
sub test_dir {
    my $self = shift;
    return $self->SUPER::test_dir() if $self->SUPER::test_dir;
    return $self->SUPER::test_dir(@_) if @_;

    $ENV{MT_TEST_DIR} ||= File::Spec->rel2abs( dirname( $0 ), $self->mt_dir );
    return $self->test_dir( $ENV{MT_TEST_DIR} );
}


=head2 config_dir

DOCUMENTATION NEEDED
dirname( $ENV{MT_CONFIG} ) || $self->mt_dir } },

=cut
sub config_dir {
    my $self = shift;
    return $self->SUPER::config_dir() if $self->SUPER::config_dir;
    return $self->SUPER::config_dir(@_) if @_;
    return $self->config_dir(
        $self->config_file ? dirname( $self->config_file )
                           : $self->mt_dir
    );
}


=head2 config_file

=item * $ENV{MT_CONFIG} = $self->config_file()

The file which contains MT config information

=cut
sub config_file {
    my $self = shift;
    return $self->SUPER::config_file() if $self->SUPER::config_file;
    return $self->SUPER::config_file(@_) if @_;
    
    my $file = $ENV{MT_CONFIG}
           || File::Spec->catfile( $self->test_dir, $self->ConfigFile );

    $file = File::Spec->rel2abs( $file, $self->mt_dir );
    
    $self->config_file( $ENV{MT_CONFIG} = $file );
}


=head2 ds_dir


=item * $ENV{MT_DS_DIR} = $self->ds_dir()

The directory containing our working test Database (if using SQLite)

=cut
sub ds_dir {
    my $self = shift;
    return $self->SUPER::ds_dir() if $self->SUPER::ds_dir;
    return $self->SUPER::ds_dir(@_) if @_;

    my $dir = File::Spec->catdir( $self->config_dir, 'db' );
    
    -d $dir or make_path( $dir, {error => \my $err} );

    return $self->ds_dir( $ENV{MT_DS_DIR} = $dir )
        unless ref $err and @$err;

    my $msg = '';
    for my $diag (@$err) {
        my ($file, $message) = %$diag;
        if ($file eq '') {
            $msg .= "General error: $message\n";
        }
        else {
            $msg .= "Could not create path $file: $message\n";
        }
    }
    return $self->error( $msg );
}

=head2 db_file

The path to our working database file (if using SQLite)

=cut
sub db_file {
    my $self = shift;
    return $self->SUPER::db_file() if $self->SUPER::db_file;
    return $self->SUPER::db_file(@_) if @_;

    $self->db_file( File::Spec->catfile( $self->ds_dir, $self->DBFile ) );
}


=head2 ref_dir

=item * $ENV{MT_REF_DIR} = $self->ref_dir()

The directory containing our pristine test Database (if using SQLite)

=cut
sub ref_dir {
    my $self = shift;
    return $self->SUPER::ref_dir() if $self->SUPER::ref_dir;
    return $self->SUPER::ref_dir(@_) if @_;

    my $dir = File::Spec->catdir( $self->config_dir, 'ref' );

    -d $dir or make_path( $dir, {error => \my $err} );

    return $self->ref_dir( $ENV{MT_REF_DIR} = $dir )
        unless $err and @$err;

    my $msg = '';
    for my $diag (@$err) {
        my ($file, $message) = %$diag;
        if ($file eq '') {
            $msg .= "General error: $message\n";
        }
        else {
            $msg .= "Could not create path $file: $message\n";
        }
    }
    return $self->error( $msg );
}

=head2 init_newdb

DOCUMENTATION NEEDED

=cut
sub init_db {
    my $self       = shift;
    my $data_class = shift || $self->DataClass();

    eval "require $data_class;"
        or die "Could not load $data_class: $@";

    -d $self->ds_dir
        or die sprintf( "DS directory not found: %s", $self->ds_dir );

    my $db_file = $self->db_file;
    if ( -f $db_file ) {
        unlink( $db_file ) or die "Error removing DBFile $db_file: ".$!;
    }

    my $key    = $data_class->Key;
    my $ref_db = File::Spec->catfile( $self->ref_dir, $key, $self->DBFile );

    my $cfg;
    if ( -f $ref_db ) {
        cp( $ref_db, $db_file ) or die "Copy failed from $ref_db to $db_file: $!";

        my $mt = MT->instance( Config => $self->config_file )
            or die "No MT object " . MT->errstr;
        MT::Object->dbi_driver->dbh(undef);

        $cfg = $mt->config;
        $cfg->read_config_db();

        die "Database mismatch, should be ".$self->db_file
            unless File::Spec->rel2abs( $self->db_file, $self->mt_dir )
                eq File::Spec->rel2abs( $cfg->Database, $self->mt_dir );
    }
    else {
        $self->init_newdb(@_) && $self->init_upgrade(@_);
        make_path( dirname( $ref_db ), { error => \(my $err) });

        if ( ref $err and @$err ) {
            my $msg = '';
            for my $diag (@$err) {
                my ($file, $message) = %$diag;
                if ($file eq '') {
                    $msg .= "General error: $message\n";
                }
                else {
                    $msg .= "Could not create path $file: $message\n";
                }
            }
            die $msg;
        }
        cp( $db_file, $ref_db ) or die "Copy failed from $db_file to $ref_db: $!";
    }
    $self;
}



=head2 init_newdb

=cut
sub init_newdb {
    my $self = shift;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    use MT;
    my $mt = MT->instance( Config => $self->config_file )
      or die "No MT object " . MT->errstr;

    my $types    = MT->registry('object_types');
    $types->{$_} = MT->model($_)
        for grep { MT->model($_) }
             map { $_ . ':meta' }
            grep { MT->model($_)->meta_pkg }
                sort keys %$types;

    my @classes = map { $types->{$_} } grep { $_ !~ /\./ } sort keys %$types;
    foreach my $class (@classes) {
        next if ref($class) eq 'ARRAY';   # TODO for now - it won't hurt
                                          # when we do driver-tests.
        if ( ! defined *{ $class . '::__properties' } ) {
            eval '# line ' 
              . __LINE__ . ' ' 
              . __FILE__ . "\n"
              . 'require '
              . $class
              or die $@;
        }
    }

    # Clear existing database tables
    my $driver = MT::Object->driver();
    my $ddl    = $driver->dbd->ddl_class;
    foreach my $class ( @classes ) {
        $class = $class->[0] if ref $class eq 'ARRAY';

        if ( $ddl->table_exists($class) ) {
            $driver->sql( $ddl->drop_table_sql($class) );
            $ddl->drop_sequence($class),;
        }
    }

    1;
}

=head2 init_upgrade

=cut
sub init_upgrade {
    my $self = shift;

    # use Carp;
    # Carp::cluck('Upgrading database '); #.Dumper(@MT::Plugins));

    # Initialize the MT database
    require MT::Upgrade;
    MT::Upgrade->do_upgrade(
        Install => 1,
        App     => __PACKAGE__,
        User    => {},
        Blog    => {}
    );

    MT->config->PluginSchemaVersion( {} );
    MT::Upgrade->do_upgrade( App => __PACKAGE__, User => {}, Blog => {} );

    eval {

        # line __LINE__ __FILE__
        # MT::Entry->remove;
        # MT::Page->remove;
        # MT::Comment->remove;
    };
    require MT::ObjectDriver::Driver::Cache::RAM;
    MT::ObjectDriver::Driver::Cache::RAM->clear_cache();

    1;
} ## end sub init_upgrade


=head2 init_data

DOCUMENTATION NEEDED

=cut

sub init_data {
    my $self = shift;
    my %params = @_;
    my $data_class = delete $params{data_class} || $self->DataClass;
    eval "require $data_class;" or croak $@;
    my $data = $data_class->new();
    $data->init( \%params ) or return $self->error( $data->errstr );
    $self->data( $data );
    return $data;
}

our $MEMCACHED_SEARCHED;
our $MEMCACHED_FAKE;
if ( $ENV{PREFILLED_CACHE} ) {
    $MEMCACHED_FAKE = $ENV{PREFILLED_CACHE};
}

=head2 init_memcached

=cut
sub init_memcached {
    my $self = shift;
    eval { require MT::Memcached; };
    if ($@) {
        die "Cannot fake MT::Memcached, as it's not available";
    }

    no warnings 'once';
    local $SIG{__WARN__} = sub { };

    my $orig_new = \&MT::Memcached::new;
    *MT::Memcached::new = sub {
        my $class = shift;
        my %param;
        my $self = bless \%param, 'MT::Memcached';
        return $self;
    };
    *MT::Memcached::instance = sub {
        my $class = shift;
        my $self  = MT::Memcached->new();
        return $self;
    };
    *MT::Memcached::is_available = sub { 1 };
    *MT::Memcached::get = sub {
        my $self = shift;
        my ($key) = @_;
        $MEMCACHED_SEARCHED->{$key} = 1;
        return $MEMCACHED_FAKE->{$key};
    };
    *MT::Memcached::get_multi = sub {
        my $self = shift;
        my @keys = @_;
        my %vals = ();
        foreach my $k (@keys) {
            $vals{$k} = $MEMCACHED_FAKE->{$k}
              if exists( $MEMCACHED_FAKE->{$k} );
        }
        return \%vals;
    };
    *MT::Memcached::add = sub {
        my $self = shift;
        my ( $key, $val, $ttl ) = @_;
        unless ( exists $MEMCACHED_FAKE->{$key} ) {
            $MEMCACHED_FAKE->{$key} = $val;
        }
    };
    *MT::Memcached::replace = sub {
        my $self = shift;
        my ( $key, $val, $ttl ) = @_;
        if ( exists $MEMCACHED_FAKE->{$key} ) {
            $MEMCACHED_FAKE->{$key} = $val;
        }
    };
    *MT::Memcached::set = sub {
        my $self = shift;
        my ( $key, $val, $ttl ) = @_;
        $MEMCACHED_FAKE->{$key} = $val;
    };
    *MT::Memcached::delete = sub {
        my $self = shift;
        my ($key) = @_;
        $MEMCACHED_FAKE->{"old$key"} = delete $MEMCACHED_FAKE->{$key};
    };
    *MT::Memcached::remove = sub {
        my $self = shift;
        my ($key) = @_;
        $MEMCACHED_FAKE->{"old$key"} = delete $MEMCACHED_FAKE->{$key};
    };
    *MT::Memcached::incr = sub {
        my $self = shift;
        my ( $key, $incr ) = @_;
        my $val = $MEMCACHED_FAKE->{$key};
        $val  ||= 0;
        $incr ||= 1;
        $MEMCACHED_FAKE->{$key} = $val + $incr;
    };
    *MT::Memcached::decr = sub {
        my $self = shift;
        my ( $key, $incr ) = @_;
        my $val = $MEMCACHED_FAKE->{$key};
        $val  ||= 0;
        $incr ||= 1;
        $MEMCACHED_FAKE->{$key} = $val - $incr;
        if ( $MEMCACHED_FAKE->{$key} < 0 ) {
            $MEMCACHED_FAKE->{$key} = 0;
        }
    };
    *MT::Memcached::inflate = sub {
        my $driver = shift;
        my ( $class, $data ) = @_;
        $class->inflate($data);
    };
    *MT::Memcached::deflate = sub {
        my $driver = shift;
        my ($obj) = @_;
        $obj->deflate;
    };

    # make sure things will pull from Memcached instead of RAM
    eval {
        require MT::ObjectDriver::Driver::Cache::RAM;
        MT::ObjectDriver::Driver::Cache::RAM->Disabled(1);
    };
}


1;

__END__
