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

use strict;
use warnings;

# Handle cwd = MT_DIR, MT_DIR/t
use lib 't/lib', 'extlib', 'lib', '../lib', '../extlib';

use Data::Dumper;
use Carp qw( longmess croak confess carp );
use File::Basename;
use File::Spec;
use List::Util   qw( first );
use Scalar::Util qw( blessed );
use File::Temp   qw( tempfile );
use File::Path   qw( make_path remove_tree );

# local $SIG{__WARN__} = \&Carp::cluck;
# local $SIG{__DIE__} = \&Carp::confess;

use Log::Log4perl::Resurrector;
# The above works for LATER loaded modules, but it's too late for this one
use Log::Log4perl qw( :resurrect );
use MT::Log::Log4perl qw(l4mtdump);
###l4p our $logger = MT::Log::Log4perl->new();

use Test::MT::Util qw( debug_handle );

sub DEBUG { 0 }

use base qw( MT::App );
use MT;

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
    # $self->revert_component_init( reinit => 0 );
    $self->SUPER::init( @_ );
    $self->override_core_methods();
    MT->set_instance( $self );
    $self->add_callback( 'post_init', 1, undef, \&add_plugin_test_libs );
    $self;
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

=head2 revert_component_init

our (
    $plugin_sig, $plugin_envelope, $plugin_registry,


);
my %Text_filters;

# For state determination in MT::Object
our $plugins_installed;

my $types = MT->registry('object_types');

=cut
sub revert_component_init {
    my $pkg   = shift;
    my %param = @_;
    my $debug = $pkg->debug_handle($param{output});
    my $mt    = MT->instance;
    # MT package scalar variables we need to reset
    my @global_scalars = qw(    plugin_sig         plugin_envelope
      plugin_registry    plugins_installed
      plugin_full_path                       );
    my $c_hash    = \%MT::Components;    # Aliased...
    my $c_arry    = \@MT::Components;    #  for...
    my $p_hash    = \%MT::Plugins;       #   brevity!
    my $inst      = \$MT::mt_inst;
    my $inst_hash = \%MT::mt_inst;
    $debug->( 'INITIAL %MT::Components: ' . Dumper([keys %$c_hash]) );

    # our %CallbackAlias;
    # our $CallbacksEnabled = 1;
    # my %CallbacksEnabled;
    # my @Callbacks;
    # our $CB_ERR;
    # my %addons;
    # our %Commenter_Auth;
    # our %Captcha_Providers;

    # We are reinitializing everything *BUT* the core component
    # so we need to preserve it before destroying the rest.
    # Die if it's not initialized because that's just wrong
    my $core = delete $c_hash->{core}; # or die "No core component found!";

    $debug->(   'Undefining all MT package scalar vars '
              . 'related to component/plugin initialization' );
    no strict 'refs';
    undef ${"MT::".$_} or $debug->("\t\$MT::$_") for @global_scalars;

    {

        # As it says in MT.pm:
        #   Reset the Text_filters hash in case it was preloaded by plugins
        #   by calling all_text_filters (Markdown in particular does this).
        #   Upon calling all_text_filters again, it will be properly loaded
        #   by querying the registry.
        no warnings 'once';
        %MT::Text_filters = ();
    }

    $debug->('Unloading plugins\' perl init scripts from %INC cache');

    # This forces both perl and MT to treat the file as if it's never been
    # loaded previously which is necessary for making MT process the plugin
    # as it does in its own init methods.
    foreach my $pdata ( values %$p_hash ) {
        my $path = first { defined($_) and /\.pl/i }
                    $pdata->{object}{ "full_path", "path" };
        next unless $path;
        delete $INC{$path} and $debug->("\t$path");
    }


    # And finally: Re-initialize %MT::Components and @MT::Components
    # with only the 'core' component and undef %MT::Plugins completely
    @MT::Components = ( $core );
    %MT::Components = ( core => $core );
    %MT::Plugins    = ();
    @MT::Plugins    = ();

    $debug->( 'Final %MT::Components: ' . Dumper([keys %$c_hash]) );

    return unless $param{reinit};

    # Find and initialize all non-core components
    #-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
    my %path_params
      = ( Config => $mt->{config_dir}, Directory => $mt->{mt_dir} );
    my $killme = sub { die "FAIL " . longmess() };

    #-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#
    eval {
        $debug->('Re-initializing addons');
        $mt->init_addons() or $killme->();

        $mt->init_config_from_db( \%path_params ) or $killme->();
        $mt->init_debug_mode;

        $debug->('Re-initializing plugins');
        $mt->init_plugins() or $killme->();

        # Set the plugins_installed flag signalling that it's
        # okay to initialize the schema and use the database.
        no warnings 'once';
        $MT::plugins_installed = 1;
    };
    die "Failed: $@" . longmess() if $@;
    $debug->('Plugins re-initialization complete');
} ## end sub revert_component_init

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

=head2 find_addon_libs

=cut
sub find_addon_libs {
    my $addons_full_path = shift;
    my @libs;
    opendir ADDONS, $addons_full_path;
    my @addons = readdir ADDONS;
    closedir ADDONS;
    for (@addons) {
        my $plugin_full_path = File::Spec->catdir( $addons_full_path, $_ );
        next unless -d $plugin_full_path;
        next if $_ eq '..';
        opendir SUBDIR, $plugin_full_path;
        my @plugin_files = readdir SUBDIR;
        closedir SUBDIR;
        for my $file (@plugin_files) {
            if ( $file eq 'lib' || $file eq 'extlib' ) {
                my $plib = File::Spec->catdir( $plugin_full_path, $file );
                unshift @libs, $plib if -d $plib;
            }
        }
    }
    return \@libs;
} ## end sub find_addon_libs

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
