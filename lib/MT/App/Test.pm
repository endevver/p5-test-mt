package MT::App::Test;

=head1 NAME

MT::App::Test - MT::App subclass for test applications

=head1 SYNOPSIS

   use MT::App::Test;

   # Brief but working code example(s) here showing the most common usage(s)
   # This section will be as far as many users bother reading, so make it as
   # educational and exemplary as possible.

=head1 DESCRIPTION

This class is an MT::App subclass responsible for initialization and
execution of test application.

=cut
use 5.010_001;
use strict;
use warnings;
# Handle cwd = MT_DIR, MT_DIR/t
use lib 't/lib', 'extlib', 'lib', '../lib', '../extlib';

use base qw( MT::App );

use Data::Dumper;
use Carp qw( longmess croak confess carp );
use File::Basename;
use File::Spec;
use List::Util   qw( first );
use Scalar::Util qw( blessed looks_like_number );
use File::Temp   qw( tempfile );
use File::Path   qw( make_path remove_tree );
use Log::Log4perl qw( :resurrect );
###l4p use Log::Log4perl::Resurrector;
###l4p use MT::Log::Log4perl qw(l4mtdump);
###l4p our $logger = MT::Log::Log4perl->new();

use Test::MT::Util qw( debug_handle );
use MT;


sub DEBUG { 0 }


my ( $CORE_TIME, $session_id );
my $session_username = '';

BEGIN {
    # Override time and sleep so we can simulate time passing without making
    # test scripts wait for real wall seconds to pass.
    *CORE::GLOBAL::time =
      sub { my ($a) = @_; $a ? CORE::time + $_[0] : CORE::time };
    *CORE::GLOBAL::sleep = sub { CORE::sleep };
}

sub id { 'testapp' }

=head2 init

=cut
sub init {
    my $self = shift;
    my %args = @_;
    $self->SUPER::init( @_ );
    $self->override_core_methods();
    MT->set_instance( $self );
    $self->add_callback( 'post_init', 1, undef, \&add_plugin_test_libs );
    $self;
}


{
    my $Database;

    sub set_database {
        my $mt = shift;
        my $cfg = $mt->{cfg};
        warn "no config yet" and return unless $cfg;
        $cfg->set( 'database', $Database->stringify );
        warn 'Database set to '.$cfg->get( 'database' );
    }

    sub init_config {
        my $mt       = shift;
        my ($param)  = @_;
        $Database = delete $param->{TestDatabase};
        warn "Got $Database from init_config params: ".$Database;

        unless ( $mt->SUPER::init_config( $param ) ) {
            warn 'Superclass init_config returned false. '
                .( $mt->errstr ? 'Error was '.$mt->errstr : 'No error tho.');
            return;
        }

        $mt->set_database();

        1;
    }
}

sub init_plugins {
    my $app = shift;
    my $cfg = $app->config;
    DEBUG and print STDERR "INITIALIZING PLUGINS\n";
    $cfg->PluginPath([ $cfg->PluginPath, "$ENV{MT_HOME}/plugins"  ]);
    $app->SUPER::init_plugins( @_ );
}

sub init_config_from_db {
    my $mt = shift;
    my ($param) = @_;
    my $cfg = $mt->config;
    # Tell any instantiated drivers to reconfigure themselves as necessary
    require MT::ObjectDriverFactory;
    if (MT->config('ObjectDriver')) {
        my $driver = MT::ObjectDriverFactory->instance;
        $driver->configure if $driver;
    } else {
        MT::ObjectDriverFactory->configure();
    }

    $cfg->read_config_db();
    undef $cfg->{_errstr};
    1;
}

=head2 init_time

=cut
sub init_time {
    $CORE_TIME = time;
    no warnings 'redefine';
    *CORE::GLOBAL::time = sub { $CORE_TIME };
    *CORE::GLOBAL::sleep = sub { $CORE_TIME += shift };
}

=head2 mt_package_hashvars_dump

=cut
{
    my $re_looped = 0;

    sub mt_package_hashvars_dump {
        my $pkg = shift;
        my $re  = $re_looped++ ? 're' : '';
        my $sep = '---' x 25;
        return
          join( "\n\n",
                $sep,
                'Components ${re}initialized: ' . Dumper( \%MT::Components ),
                'Plugins ${re}initialized: ' . Dumper( \%MT::Plugins ),
                $sep,
          );
    }
}

=head2 progress

=cut
sub progress { }

=head2 reset_table_for

=cut
sub reset_table_for {
    my $self = shift;
    my $debug = $self->debug_handle();
    for my $class (@_) {
        my $driver    = $class->dbi_driver;
        my $dbh       = $driver->rw_handle;
        my $ddl_class = $driver->dbd->ddl_class;

        $dbh->{pg_server_prepare} = 0
            if $ddl_class =~ m/Pg/;

        if ($driver->table_exists($class)) {
            $debug->( "Dropping $class table" );
            $dbh->do( $ddl_class->drop_table_sql($class) )
              or die $dbh->errstr;
        }

        $debug->( "Re-creating $class table" );
        $dbh->do( $ddl_class->create_table_sql($class) ) or die $dbh->errstr;

        for ($ddl_class->index_table_sql($class)) {
            $debug->( "Running SQL on $class table: $_" );
            $dbh->do($_) or die $dbh->errstr
        }

        $debug->( "Dropping sequence on $class table" );
        $ddl_class->drop_sequence($class);

        $debug->( "Creating sequence on $class table" );
        $ddl_class->create_sequence($class);    # may do nothing
    }
}

=head2 make_objects

=cut
sub make_objects {
    my $self     = shift;
    my @obj_data = @_;

    for my $data (@obj_data) {
        if ( my $wait = delete $data->{__wait} ) {
            sleep($wait);
        }
        my $class = delete $data->{__class};
        my $obj   = $class->new;
        $obj->set_values($data);
        $obj->save() or die "Could not save test Foo: ", $obj->errstr, "\n";
    }
}

=head2 get_current_session

=cut
sub get_current_session {
    require MT::Session;
    my $sess = MT::Session::get_unexpired_value(
        MT->config->UserSessionTimeout,
        {
            id   => $session_id,
            kind => 'US'
        }
    );
    return $sess;
}

=head2 _run_rpt

=cut
sub _run_rpt {
    `perl ./tools/run-periodic-tasks`;

    1;
}

=head2 _run_tasks

=cut
sub _run_tasks {
    my ($tasks) = @_;
    return unless $tasks;
    require MT::Session;
    for my $t (@$tasks) {
        MT::Session->remove( { id => "Task:$t" } );
    }

    require MT::TaskMgr;
    MT::TaskMgr->run_tasks(@$tasks);
}

=head2 _run_app

=cut
sub run_app {
    my ( $class, $params, $level ) = @_;
    Carp::croak "run_app is not implemented";
    $level ||= 0;
    require CGI;
    my $cgi              = CGI->new;
    my $follow_redirects = 0;
    my $max_redirects    = 10;
    while ( my ( $k, $v ) = each(%$params) ) {
        if ( ref($v) eq 'ARRAY' && $k ne '__test_upload' ) {
            $cgi->param( $k, @$v );
        }
        elsif ( $k eq '__test_follow_redirects' ) {
            $follow_redirects = $v;
        }
        elsif ( $k eq '__test_max_redirects' ) {
            $max_redirects = $v;
        }
        elsif ( $k eq '__test_upload' ) {
            my ( $param, $src ) = @$v;
            my $seqno =
              unpack( "%16C*",
                join( '', localtime, grep { defined $_ } values %ENV ) );
            my $filename = basename($src);
            no warnings 'once';
            $CGITempFile::TMPDIRECTORY = '/tmp';
            my $tmpfile = new CGITempFile($seqno) or die "CGITempFile: $!";
            my $tmp     = $tmpfile->as_string;
            my $cgi_fh  = Fh->new( $filename, $tmp, 0 ) or die "FH? $!";

            {
                local $/ = undef;
                open my $upload, "<", $src or die "Can't open $src: $!";
                my $d = <$upload>;
                close $upload;
                print $cgi_fh $d;

                seek( $cgi_fh, 0, 0 );
            }

            $cgi->param( $param, $cgi_fh );
        }
        else {
            $cgi->param( $k, $v );
        }
    }
    eval "require $class;";
    my $app = $class->new( CGIObject => $cgi );
    MT->set_instance($app);

    # nix upgrade required
    # seems to be hanging around when it doesn't need to be
    $app->{init_request} = 0;    # gotta set this to force the init request
    $app->init_request( CGIObject => $cgi );
    $app->{request_method} = $params->{__request_method}
      if ( $params->{__request_method} );
    $app->run;

    my $out = $app->{__test_output};

    # is the response a redirect
    if (   $out
        && $out =~ /^Status: 302 Moved\s*$/smi
        && $follow_redirects
        && $level < $max_redirects )
    {
        if ( $out =~ /^Location: \/cgi-bin\/mt\.cgi\?(.*)$/smi ) {
            my $location = $1;
            $location =~ s/\s*$//g;
            my @params = split( /&/, $location );
            my %params =
              map { my ( $k, $v ) = split( /=/, $_, 2 ); $k => $v } @params;

            # carry over the test parameters
            $params{$_} = $params->{$_}
              foreach ( grep { /^__test/ } keys %$params );

            # nix any any all caches!!
            require MT::Object;
            MT::Object->driver->clear_cache;
            $app->request->reset;

            # anything else here??
            undef $app;

            $app = _run_app( $class, \%params, $level++ );
        }
    }

    return $app;
}

=head2 add_plugin_test_libs

=cut
sub add_plugin_test_libs {
    require MT::Plugin;
    foreach my $p ( MT::Plugin->select ) {
        my $t_lib = File::Spec->catdir( $p->path, 't', 'lib' );
        unshift @INC, $t_lib if ( -d $t_lib );
    }
    1;
}

=head2 override_core_methods

=cut
sub override_core_methods {
    my $self = shift;
    no warnings 'once';
    local $SIG{__WARN__} = sub { };

    *MT::App::print = sub {
        my $app = shift;
        $app->{__test_output} ||= '';
        $app->{__test_output} .= join( '', @_ );
    };

    my $orig_login = \&MT::App::login;
    *MT::App::login = sub {
        my $app = shift;
        if ( my $user = $app->query->param('__test_user') ) {

            # attempting to fake user session
            if (   !$self->session_id
                 || $user->name ne $self->session_username
                 || $app->query->param('__test_new_session') )
            {
                $app->start_session( $user, 1 );
                $self->session_id( $app->{session}->id );
                $self->session_username( $user->name );
            }
            else {
                $app->session_user( $user, $self->session_id );
            }
            $app->query->param( 'magic_token', $self->session_id );
            $app->user($user);
            return ( $user, 0 );
        }
        $orig_login->( $app, @_ );
    };
}

1;

__END__
