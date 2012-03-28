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
use strict;
use warnings;
use Carp;
use Test::Most;
use Try::Tiny;
use Data::Dumper::Names;

use base qw( Class::Accessor::Fast MT::ErrorHandler );

BEGIN {
    my $mt = $ENV{MT_HOME} || '';
    $mt and $mt =~ s{/*$}{/}i;   # Trailing slash; 
                                 # i is TextMate syntax coloring fix
    unshift( @INC, (
        "${mt}lib",     "${mt}extlib",
        "${mt}t/lib",   "${mt}t/extlib", 
    ));
}

=head1 SUBROUTINES/METHODS

sub init { }
sub test_basename {
sub finish { }

=cut

# sub import {
#     my $pkg     = shift;
#     $pkg        = ref( $pkg ) || $pkg;
#     my $callpkg = caller(0);
#     my $from    = (caller(1))[3];
# 
#     print STDERR "\n\n".Dumper({ pkg => $pkg, callpkg => $callpkg, arg => \@_, from => $from });
# 
#     my %modules_to_load = map { $_ => 1 } qw/
#         my @exclude_symbols;
#         
#     /;
#     warnings->import;
#     strict->import;
# 
#     foreach my $module (keys %modules_to_load) {
#         # some Test modules we use are naughty and don't use Exporter.
#         # See RT#61145.
#         if ($module->isa('Exporter')) {
#             eval "require $module; import $module;";
#         } else {
#             eval "use $module";
#         }
# 
#         if ( my $error = $@) {
#             require Carp;
#             Carp::croak($error);
#         }
#         no strict 'refs';
#         my %count;
#         $count{$_}++ foreach @{"${module}::EXPORT"}, @exclude_symbols;
#         # Note: export_to_level would be better here.
#         push @EXPORT => grep { $count{$_} == 1 } @{"${module}::EXPORT"};
#     }
# print 'EXPORT: '.Dumper( @export );
# 
#     # 'magic' goto to avoid updating the callstack
#     goto &Test::Builder::Module::import;
# 
#     #-----------------------------------------------------
# 
# 
# 
#     print STDERR "\n\n".Dumper({ pkg => $pkg, callpkg => $callpkg, arg => \@_, from => $from });
# 
#     print "Starting imports for $pkg\n";
#     foreach my $m (qw( warnings strict Carp Data::Dumper::Names Test::Most )) {
#         # next if exists $main::{$m};
#         print "*    Importing $m\n"; 
#         eval "require $m;"
#             or die "Could not import $m: $@"; 
#         $m->can('import') 
#             ?  ( try { $m->import } catch { die "Failed it with $m $@" })
#             :  ( print "$m does not have an import method" );
#     }
#     print "Imports complete for $pkg\n";
# 
# 
#     print "ARE WE EXPORTING???";
#     if (  @_ and $_[0] eq "import") {
#         print "---> Exporting import into package of caller: ".$callpkg."\n";
#         no strict 'refs';
#         *{$callpkg."::import"} = \&import unless $callpkg->can('import');
# die "No import in $callpkg" unless $callpkg->can('import');
#         return $callpkg->import();
#     }
#     else { print "---> Not exporting this time!\n" }
#     return;
# 
#     #-----------------------------------------------------
# 
#     # no strict 'refs';
#     # *{"$pkg\::Dumper"} = \&Dumper;
# 
# 
#     # # We *need* to treat @{"$pkg\::EXPORT_FAIL"} since Carp uses it :-(
#     # my $exports = \@{"$pkg\::EXPORT"};
#     # # But, avoid creating things if they don't exist, which saves a couple of
#     # # hundred bytes per package processed.
#     # my $fail = ${$pkg . '::'}{EXPORT_FAIL} && \@{"$pkg\::EXPORT_FAIL"};
#     # return export $pkg, $callpkg, @_
#     #   if $Verbose or $Debug or $fail && @$fail > 1;
#     # my $export_cache = ($Cache{$pkg} ||= {});
#     # my $args = @_ or @_ = @$exports;
#     # 
#     # if ($args and not %$export_cache) {
#     #   s/^&//, $export_cache->{$_} = 1
#     #     foreach (@$exports, @{"$pkg\::EXPORT_OK"});
#     # }
#     # my $heavy;
#     # # Try very hard not to use {} and hence have to  enter scope on the foreach
#     # # We bomb out of the loop with last as soon as heavy is set.
#     # if ($args or $fail) {
#     #   ($heavy = (/\W/ or $args and not exists $export_cache->{$_}
#     #              or $fail and @$fail and $_ eq $fail->[0])) and last
#     #                foreach (@_);
#     # } else {
#     #   ($heavy = /\W/) and last
#     #     foreach (@_);
#     # }
#     # return export $pkg, $callpkg, ($args ? @_ : ()) if $heavy;
#     # local $SIG{__WARN__} = 
#     #   sub {require Carp; &Carp::carp} if not $SIG{__WARN__};
#     # # shortcut for the common case of no type character
#     # *{"$callpkg\::$_"} = \&{"$pkg\::$_"} foreach @_;
# 
# }

sub init { shift }


sub test_basename {
    my $self = shift;
    (split("::", ( ref $self || $self )))[1];
}

sub finish { shift }

our $session_id;
our $session_username = '';

=head2 init_app

=cut
sub init_app {
    my $pkg   = shift;
    my ($cfg) = @_;
    $cfg    ||= $ENV{MT_CONFIG};

    my $app_class = $ENV{MT_APP} ||= 'MT::App::Test';
    eval "require $app_class; 1;" or die "Can't load $app_class: $@";
    my $app = $app_class->construct( Config => $cfg, App => $app_class );
    return $app;

    # my $app = $app_class->new( Config => $cfg, App => 'MT::App::Test' );
    # 
    # # kill __test_output for a new request
    # require MT;
    # MT->add_callback(
    #     "${app}::init_request",
    #     1, undef,
    #     sub {
    #         $_[1]->{__test_output}    = '';
    #         $_[1]->{upgrade_required} = 0;
    #     }
    # ) or die( MT->errstr );
    # {
    #     no warnings 'once';
    #     local $SIG{__WARN__} = sub { };
    #     my $orig_login = \&MT::App::login;
    #     *MT::App::print = sub {
    #         my $app = shift;
    #         $app->{__test_output} ||= '';
    #         $app->{__test_output} .= join( '', @_ );
    #     };
    #     *MT::App::login = sub {
    #         my $app = shift;
    #         if ( my $user = $app->param('__test_user') ) {
    # 
    #             # attempting to fake user session
    #             if (  !$session_id
    #                 || $user->name ne $session_username
    #                 || $app->param('__test_new_session') )
    #             {
    #                 $app->start_session( $user, 1 );
    #                 $session_id       = $app->{session}->id;
    #                 $session_username = $user->name;
    #             }
    #             else {
    #                 $app->session_user( $user, $session_id );
    #             }
    #             $app->param( 'magic_token', $session_id );
    #             $app->user($user);
    #             return ( $user, 0 );
    #         }
    #         $orig_login->( $app, @_ );
    #     };
    # 
    # }
    # die "App = $app" unless ref $app eq __PACKAGE__;
    # MT->set_instance( $app );
}

=head2 init_cms

=cut
sub init_cms {
    my $pkg = shift;
    my ($cfg) = @_;

    require MT::App::CMS;
    MT::App::CMS->instance( $cfg ? ( Config => $cfg ) : () );
}


1;

__END__
