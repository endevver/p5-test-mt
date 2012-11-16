package Pure::Test::MT::Environment;

use base qw( Class::Accessor );


__PACKAGE__->mk_accessors(
# Obj Attributes        %ENV            Description
    'mt_dir'        ,#  MT_HOME         MT directory
    'test_dir'      ,#  MT_TEST_DIR     Base directory for the tests
    'config_dir'    ,#  MT_CONFIG       MT config file directory
    'config_file'   ,#                  MT config file
    'ds_dir'        ,#  MT_DS_DIR       Datasource (live DB) directory
    'ref_dir'       ,#  MT_REF_DIR      Reference DB directory
    'db_file'       ,#                  Absolute path to database file
    'data'          ,#                  Test data
);

#########################################################################
package Test::MT::Environment;

=head1 NAME

Test::MT::Environment - Class representing the environment for all MT tests

=head1 SYNOPSIS

    use Test::MT::Environment;
    my $env = Test::MT::Environment->new();
    $env->init();

=head1 DESCRIPTION

This class is instantiated by Test::MT::Base and available via the env()
method of its object instance

    use parent 'Test::MT::Base';
    my $test = __PACKAGE__->construct_default();
    print blessed $test->env;    # outputs Test::MT::Environment!

=head1 METHODS

=over 4


=item * mt_dir

MT_HOME         MT directory

=item * test_dir

MT_TEST_DIR     Base directory for the tests

=item * config_dir

MT_CONFIG       MT config file directory

=item * config_file

MT config file

=item * ds_dir

MT_DS_DIR       Datasource (live DB) directory

=item * ref_dir

MT_REF_DIR      Reference DB directory

=item * db_file

Absolute path to database file

=item * data

Test data

=back

=cut

sub DEBUG() { 0 }

use 5.010_001;
use strict;
use warnings;
use Data::Dumper;
use File::Spec;
use Path::Class;
use Carp            qw( croak cluck carp confess );
use File::Basename  qw( dirname basename );
use File::Path      qw( make_path remove_tree );
use Cwd             qw( getcwd );
use FindBin         qw( $Bin );
use File::Copy      qw( cp );
use autodie         qw(:all);
use Test::MT::Util  qw( debug_handle );

use base qw( Pure::Test::MT::Environment
             Class::Data::Inheritable
             MT::ErrorHandler );

my @ENV_VARS = qw( MT_HOME  MT_TEST_DIR  MT_CONFIG  MT_DS_DIR  MT_REF_DIR );

use Log::Log4perl qw( :resurrect );            # Works on this module
###l4p use Log::Log4perl::Resurrector;         # Works on modules which use this module
###l4p use MT::Log::Log4perl qw( l4mtdump );
###l4p our $logger = MT::Log::Log4perl->new();

__PACKAGE__->mk_classdata( %$_ )
    for (
            # Use different DB filenames for each process to allow
            # parallel test execution.  e.g. mt-727181.db
            { DBFile        => "mt-$$.db"                            },
            { ConfigFile    => 'test.cfg'                            },
            { DatabaseClass => join('::', __PACKAGE__, 'Database')   },
            { DataClass     => do {
                                    (my $p = __PACKAGE__) =~ s{Environment}{Data::YAML};
                                    $p;
                                },
            }
        );

=head1 SUBROUTINES/METHODS

=head2 init

This method initializes the path-related variables necessary to run MT and
locate our own modules.

=cut
sub init {
    my $self = shift;
    $self->init_paths() or return;
    $self;
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
    DEBUG() && $self->show_variables;

    $self->setup_db_file();
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

    die "MT_HOME environment variable not set" unless $ENV{MT_HOME};

    my $dir = dir( $ENV{MT_HOME} )->absolute;

    -d $dir
        or return $self->error('Bad MT_HOME directory: '. $ENV{MT_HOME} );

    chdir $dir
        or die "Can't cd to MT_HOME directory, $dir: $!\n";

    return $self->mt_dir( $ENV{MT_HOME} = "$dir" );
}


=head2 test_dir

=item * $ENV{MT_TEST_DIR} = $self->test_dir()

Root directory containing tests

=cut
sub test_dir {
    my $self = shift;
    return $self->SUPER::test_dir() if $self->SUPER::test_dir;
    return $self->SUPER::test_dir( dir(@_) ) if @_;

    $ENV{MT_TEST_DIR} ||= file($0)->parent->absolute( $self->mt_dir )->stringify;
    return $self->test_dir( $ENV{MT_TEST_DIR} );  # From FindBin
}
# ENV MT_CONFIG: /Users/jay/Projects/SmartDirectory/t/test.cfg
# ENV MT_REF_DIR: /Users/jay/Projects/SmartDirectory/t/ref
# ENV MT_TEST_DIR: /Users/jay/Projects/SmartDirectory/t


=head2 config_dir

DOCUMENTATION NEEDED
dirname( $ENV{MT_CONFIG} ) || $self->mt_dir } },
Path::Class::File
=cut
sub config_dir {
    my $self = shift;
    return $self->SUPER::config_dir() if $self->SUPER::config_dir;
    return $self->SUPER::config_dir( dir( @_ )) if @_;
    return $self->config_dir(
        $self->config_file ? file( $self->config_file )->parent
                           :  $self->mt_dir
    );
}


=head2 config_file

=item * $ENV{MT_CONFIG} = $self->config_file()

The file which contains MT config information

=cut
sub config_file {
    my $self = shift;
    return $self->SUPER::config_file() if $self->SUPER::config_file;
    return $self->SUPER::config_file( file(@_) ) if @_;

    my $file = file(     $ENV{MT_CONFIG}
                    // ( $self->test_dir, $self->ConfigFile )
      )->absolute( $self->mt_dir );
    $self->config_file( $ENV{MT_CONFIG} = "$file" );
}


=head2 ds_dir


=item * $ENV{MT_DS_DIR} = $self->ds_dir()

The directory containing our working test Database (if using SQLite)

=cut
sub ds_dir {
    my $self = shift;
    return $self->SUPER::ds_dir() if $self->SUPER::ds_dir;
    return $self->SUPER::ds_dir( dir( @_ )) if @_;

    my $dir = dir( $ENV{MT_DS_DIR} || ($self->config_dir, 'db') );

    -d $dir or make_path( $dir, {error => \my $err} );

    return $self->ds_dir( $ENV{MT_DS_DIR} = "$dir" )
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
    return $self->SUPER::db_file( file(@_) ) if @_;

    my $db_file = file( $self->ds_dir, $self->DBFile );
    -e $db_file and die "Database file $db_file already exists.  Aborting!";

    $self->db_file( $db_file );
}


=head2 ref_dir

=item * $ENV{MT_REF_DIR} = $self->ref_dir()

The directory containing our pristine test Database (if using SQLite)

=cut
sub ref_dir {
    my $self = shift;
    return $self->SUPER::ref_dir() if $self->SUPER::ref_dir;
    return $self->SUPER::ref_dir( dir(@_) ) if @_;

    my $dir = dir( $self->config_dir, 'ref' );

    -d $dir or make_path( $dir, {error => \my $err} );

    return $self->ref_dir( $ENV{MT_REF_DIR} = "$dir" )
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


=head2 app_class

DOCUMENTATION NEEDED

=cut
sub app_class {
    my $self      = shift;
    my $app_class = $ENV{MT_APP} ||= 'MT::App::Test';
    eval "require $app_class; 1;" or die "Can't load $app_class: $@";
    $app_class;
}

=head2 setup_db_file

DOCUMENTATION NEEDED

=cut
sub setup_db_file {
    my $self       = shift;
    my $data_class = shift || $self->DataClass();
    my $db_file    = $self->db_file;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    ###l4p $logger->info("Initializing data class $data_class");
    eval "require $data_class;"
        or die "Could not load $data_class: $@";
    my $key     = $data_class->Key;
    my $ref_db  = file( $self->ref_dir, "$key.db" );
    ###l4p $logger->debug("ref_db path: $ref_db");
    ###l4p $logger->debug("db_file path: $db_file");

    # An empty database is just as good as a non-existent one...
    -e -z $_ and unlink($_) for ( $db_file, $ref_db );

    $self->sync_ref_db( $ref_db );

    # # DB file exists, is read/write and non-zero-byte length
    # if ( $db_file and -e -w -r -s $db_file ) {
    #     ###l4p $logger->info('Found existing DB to use: '.$db_file );
    # 
    #     ###l4p $logger->info("Copying existing DB to ref DB $ref_db ("
    #     ###l4p              .(-s $ref_db)." bytes); copying to $db_file");
    #     unlink( $ref_db ) if -e -w $ref_db;
    #     cp( $db_file, $ref_db );
    # }
    # elsif ( $ref_db and -e -w -r -s $ref_db ) {
    #     cp( $ref_db, $db_file );
    # }
    # 
    return $self;
}

sub sync_ref_db {
    my $self    = shift;
    my $ref_db  = shift;
    my $db_file = $self->db_file;

    state %ref_db;
    $ref_db = $ref_db{Scalar::Util::refaddr($self)} ||= $ref_db;

    # DB file exists, is read/write and non-zero-byte length
    if ( ! -e "$ref_db" and -e -r -s "$db_file" ) {
        ###l4p $logger->info('Found existing DB to use: '.$db_file );

        ###l4p $logger->info("Copying existing DB to ref DB $ref_db ("
        ###l4p              .(-s $ref_db)." bytes); copying to $db_file");
        # unlink( $ref_db ) if -e -w $ref_db;
        cp( $db_file, $ref_db );
    }
    elsif ( ! -e "$db_file" and -e -r -s $ref_db ) {
        cp( $ref_db, $db_file );
    }
    $self->ls_db();
}


=head2 init_db

DOCUMENTATION NEEDED

=cut
sub init_db {
    my $self       = shift;
    my $data_class = shift || $self->DataClass();
    my $db_file    = $self->db_file;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    # local $Carp::Verbose = 8;
    # DEBUG and print STDERR 'In init_db '.Carp::longmess();
    ###l4p $logger->debug('In init_db called from '.(scalar caller));


    if ( -e -r -w -s $db_file ) {
        # use MT ();
        # my $mt = MT->instance( Config => $self->config_file )
        #   or die "No MT object " . MT->errstr;

        ###l4p $logger->info("Initializing upgrade");
        # $self->init_upgrade(@_);
        $self->sync_ref_db();
        return $self ;
    }
    elsif ( -e $db_file ) {
        unlink( $db_file );
    }

    # $self->init_newdb(@_);
    # 
    # Carp::confess("Could not initialize database $db_file")
    #     unless -e -r -s $db_file;
    # 
    # $self->sync_ref_db();
    # 
    $self;
}

=head2 init_newdb

DOCUMENTATION NEEDED

=cut
sub init_newdb {
    my $self = shift;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    use MT ();
    my $mt = MT->instance( Config => $self->config_file )
      or die "No MT object " . MT->errstr;

    my $types    = MT->registry('object_types');
    ###l4p $logger->debug('object_types $types: ', l4mtdump($types));

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
            ###l4p $logger->info("REQUIRING $class");
            eval '# line '
              . __LINE__ . ' '
              . __FILE__ . "\n"
              . 'require '
              . $class
              or die $@;
        }
    }
    $self->ls_db();

    # Clear existing database tables
    my $driver = MT::Object->driver();
    my $ddl    = $driver->dbd->ddl_class;
    ###l4p $logger->debug('Driver: ', l4mtdump($driver));
    ###l4p $logger->debug('DDL class: ', l4mtdump($ddl));

    foreach my $class ( @classes ) {
        $class = $class->[0] if ref $class eq 'ARRAY';
        if ( $ddl->table_exists($class) ) {
            ###l4p $logger->info("Dropping $class table and sequence");
            $driver->sql( $ddl->drop_table_sql($class) );
            $ddl->drop_sequence($class),;
        }
        else {
            ###l4p $logger->info("No table to drop for $class");
        }
    }

    ###l4p $logger->info("Initializing upgrade");
    $self->init_upgrade(@_);
    $self->ls_db();

    1;
}

=head2 init_upgrade

DOCUMENTATION NEEDED

=cut
sub init_upgrade {
    my $self = shift;

    # Initialize the MT database
    require MT::Upgrade;
    MT::Upgrade->do_upgrade(
        Install => 1,
        App     => __PACKAGE__,
        User    => {},
        Blog    => {}
    );
    $self->ls_db();

    MT->config->PluginSchemaVersion( {} );
    MT::Upgrade->do_upgrade( App => __PACKAGE__, User => {}, Blog => {} );
    $self->ls_db();

    eval {
        # line __LINE__ __FILE__
        # MT::Entry->remove;
        # MT::Page->remove;
        # MT::Comment->remove;
    };
    require MT::ObjectDriver::Driver::Cache::RAM;
    MT::ObjectDriver::Driver::Cache::RAM->clear_cache();
    $self->ls_db();

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


sub ls_db {
    my $self = shift;
    my ($ds, $ref) = ($self->ds_dir, $self->ref_dir);

    state $last_res;
    my $res = `find $ds $ref -type f -ls  2>/dev/null`;

    my $fmt = $res eq ($last_res||'')   ? "%s (%d) Same as above\n"
                                        : "%s (%d)\n  %s\n";
    my $msg = sprintf $fmt, (caller(1))[3], __LINE__, $res;
    DEBUG and print STDERR $msg;

    ###l4p local $Log::Log4perl::caller_depth =
    ###l4p       $Log::Log4perl::caller_depth + 1;
    ###l4p $logger->debug($msg);

    $last_res = $res;
}


sub progress {
    DEBUG and Carp::carp( join('; ', @_));
}

sub error {
    my $self = shift;
    Carp::cluck( join( '. ', $@ ));
    $self->SUPER::error(@_);
}


sub show_variables {
    my $self = shift;
    return unless DEBUG;
    print STDERR "# ENV $_: $ENV{$_}\n" foreach sort @ENV_VARS;
    print STDERR map { "# VAR ".join(': ', @$_)."\n" }
       map {[ $_ => $self->$_ ]}
       qw(test_dir ConfigFile mt_dir);
}

sub DESTROY {
    my $self = shift;
    return unless -e $self->db_file;
    DEBUG and warn "Removing database ".$self->db_file;
    unlink( $self->db_file );
}

1;

__END__
