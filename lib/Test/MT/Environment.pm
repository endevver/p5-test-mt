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
use Scalar::Util;
use Test::MT::Util  qw( debug_handle );

use base qw( Pure::Test::MT::Environment
             Class::Data::Inheritable   );

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
    $self->setup_db_file();
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
    $ENV{MT_HOME}     = $self->mt_dir();
    $ENV{MT_TEST_DIR} = $self->test_dir();
    $ENV{MT_CONFIG}   = $self->config_file();
    $ENV{MT_DS_DIR}   = $self->ds_dir();
    $ENV{MT_REF_DIR}  = $self->ref_dir();
    DEBUG() && $self->show_variables;
    1;
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

    # An empty database is just as good as a non-existent one...
    -e -z $_ and unlink($_) for ( $db_file, $ref_db );

    $self->sync_ref_db( $ref_db );

    return $self;
}



=head2 sync_ref_db

DOCUMENTATION NEEDED

=cut
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
}


=head2 mt_dir

=item * $ENV{MT_HOME} = $self->mt_dir()

MT home directory

=cut
sub mt_dir {
    my $self = shift;
    return $self->SUPER::mt_dir() if $self->SUPER::mt_dir;
    return $self->SUPER::mt_dir(@_) if @_;

    $ENV{MT_HOME}
        or die "MT_HOME environment variable not set";

    my $dir = dir( $ENV{MT_HOME} )->absolute;

    -d $dir
        or die 'Bad MT_HOME directory: '. $ENV{MT_HOME};

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


=head2 config_dir

DOCUMENTATION NEEDED
dirname( $ENV{MT_CONFIG} ) || $self->mt_dir } },
Path::Class::File
=cut
sub config_dir {
    my $self = shift;
    return $self->SUPER::config_dir if $self->SUPER::config_dir;
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

    my @paths = grep { -e -r -s } 
                 map { file( @$_ )->absolute( $self->mt_dir ) }
                 (
                    defined $ENV{MT_CONFIG} ? [ $ENV{MT_CONFIG} ] : (),
                    [ $self->test_dir, $self->ConfigFile ]
                );

    $self->config_file( $ENV{MT_CONFIG} = shift @paths );
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
    die $msg;
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
    die $msg;
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

    MT->config->PluginSchemaVersion( {} );
    MT::Upgrade->do_upgrade( App => __PACKAGE__, User => {}, Blog => {} );

    # eval {
        # line __LINE__ __FILE__
        # MT::Entry->remove;
        # MT::Page->remove;
        # MT::Comment->remove;
    # };
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
    $data->init( \%params ) or die $data->errstr;
    $self->data( $data );
    return $data;
}

sub progress {
    DEBUG and Carp::carp( join('; ', @_));
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
