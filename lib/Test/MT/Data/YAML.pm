package Test::MT::Data::YAML;

use strict;
use warnings;
use Carp;
use Data::Dumper;
use YAML::Tiny;
use Try::Tiny;
use Test::More;

use base qw( Test::MT::Data );

( my $key = lc(__PACKAGE__) ) =~ s{:+}{-}g;
__PACKAGE__->mk_classdata( Key => $key );

use constant DEBUG => 1;

#my $data = {
#    blogs => { blog_key => { values => { name => 'Blog Name' } } },
#    roles => {
#        role_key => {
#            values => {
#                name        => 'Role Name',
#                description => 'Role Description'
#            },
#            permissions => ( 'list', 'of', 'permissions' ),
#        },
#    },
#    groups => { group_key => { values => { name => 'Group Name' } } },
#    users  => {
#        user_key => {
#            values => { name     => 'User Name' },
#            roles  => { blog_key => [ 'role_key', 'role_key' ] }
#        }
#    },
#    entries =>
#        { entry_key => { title => 'Entry Title', text => 'Entry Text!!' } },
#};

=head2 init_data

DOCUMENTATION NEEDED

=cut
sub init {
    my $self = shift;
    my $args = shift || {};
    $args = { yaml => $args } if $args and ! ref $args;

    my $extract_from_yaml = sub {
        my $y = shift || [];
        croak "Unexpected YAML object state: ".$y unless ref $y;
        shift @$y while @$y && ( ref( $y->[0] ) ne 'HASH' );
        return $y;
    };

    my $data = [];
    if ( $args->{yaml} ) {
        my $yaml = try {
            YAML::Tiny->read_string( $args->{yaml} )
        }
        catch {
            die sprintf(
                'Error reading yaml string: %s %s',
                ( YAML::Tiny->errstr || $_ || $! ), $args->{yaml},
            );
        };
        $data = $extract_from_yaml->($yaml);
    }
    elsif ( $args->{file} ) {
        my $file = $args->{file};
        $file = File::Spec->rel2abs( $file, $ENV{MT_TEST_DIR} );
        my $yaml = try {
            YAML::Tiny->read( $file )
        }
        catch {
            die "Error reading $file ($_): " . ( YAML::Tiny->errstr ||$_ || $! );
        };
        $data = $extract_from_yaml->($yaml);
    }
    elsif ( $args->{data} ) {
        $data = $args->{data};
    }

    $self->data( shift @$data );
    $self;
}

=head2 install

DOCUMENTATION NEEDED

=cut
sub install {
    my $self     = shift;
    my $data     = $self->data     || $self->data({});
    my $env_data = $self->env_data || $self->env_data({});

    my @ordered_types = (
        # Blogs first since they don't depend on users/group3s/roles
        { 'blog'  => 'blogs'   },
        # Roles next
        { 'role'  => 'roles'   },
        # Groups next so that they can be linked to blogs and roles
        # now if need be
        { 'group' => 'groups'  },
        # Users next so that they can be linked (associated) with blogs,
        # roles or groups.
        { 'user'  => 'users'   },
        # Entries - Last but not least, the class with the most dependencies
        { 'entry' => 'entries' },
        # Tags - Which depends on entries
        { 'tag'   => 'tags' },
    );

    foreach ( @ordered_types ) {
        my ( $type, $plural ) = each %$_;
        DEBUG and diag "Starting $type creation...";
        $env_data->{$plural} = $self->create_objects( $type )
            if MT->model( $type ) && $data->{objects}{$plural};
    }
    $self->env_data( $env_data );
}


=head2 create_objects

DOCUMENTATION NEEDED

=cut
sub create_objects {
    my $self        = shift;
    my ( $kind )    = @_;
    my $plural      = $kind eq 'entry' ? 'entries' : "${kind}s";
    my $roster = $self->data->{objects}{$plural};
    my $meth        = $self->can('create_' . $kind);
    my %created;
    foreach my $key ( keys %$roster ) {
        my $member_info = $roster->{$key};
        my $obj = $self->$meth( $member_info );
        if ( $obj->id ) {
            $member_info->{values}{id} = $obj->id;
            DEBUG and diag "\tSaved $kind ID ".$obj->id;
        }
        $created{$key} = $member_info;
    }
    return \%created;
}

=head2 create_role

DOCUMENTATION NEEDED

=cut
sub create_role {
    my $self     = shift;
    my ( $data ) = @_;
    my $v = $data->{values} or croak('No values for role');
    my $role = MT->model('role')->get_by_key( { name => $v->{name} } );
    $role->set_values($v);

    $role->clear_full_permissions;
    $role->set_these_permissions( $data->{permissions} );
    if ( $v->{name} =~ m/^System/ ) {
        $role->is_system(1);
    }
    $role->role_mask( $data->{role_mask} )
        if exists $data->{role_mask};
    $role->save or croak $role->errstr;
    return $role;
}


=head2 create_user

DOCUMENTATION NEEDED

=cut
sub create_user {
    my $self     = shift;
    my ( $data ) = @_;
    my $v        = $data->{values} or croak('No values for user');
    my $env_data = $self->env_data;
    my $user     = MT->model('author')->get_by_key( { name => $v->{name} } );
    my $pwd      = delete $v->{password} || "password";
    
    $user->set_values($v);
    $user->set_password($pwd);
    $user->save or croak $user->errstr;

    if ( $data->{roles} ) {
        my $Association = MT->model('association');
        my $Blog = MT->model('blog');
        foreach my $blog_key ( keys %{ $data->{roles} } ) {
            my $blog_id = $env_data->{blogs}{$blog_key}{values}{id};
            my $blog = $Blog->load($blog_id)
                or confess(sprintf 'Cannot setup user roles for user %s: '
                               . 'cannot get blog %s',
                               $user->name, $blog_key );
            foreach my $role_key ( @{ $data->{roles}->{$blog_key} } ) {
                my $role = $env_data->{roles}->{$role_key}
                        || MT->model('role')->load( { name => $role_key } )
                    or confess(sprintf  'Cannot setup user roles for user %s: '
                                    . 'cannot get role %s',
                                      $user->name, $role_key );

                my $assoc = $Association->link( $user => $blog => $role );
                # TODO create_association
            }
        }
    }
    return $user;
}


=head2 create_blog

DOCUMENTATION NEEDED

=cut
sub create_blog {
    my $self     = shift;
    my ( $data ) = @_;
    my $v = $data->{values} or croak('No values for blog');
    my $blog = MT->model('blog')->get_by_key( { name => $v->{name} } );
    $blog->set_values($v);
    $blog->save or croak( $blog->errstr );
    return $blog;
}


=head2 create_group

DOCUMENTATION NEEDED

=cut
sub create_group {
    my $self     = shift;
    my ( $data ) = @_;
    my $v = $data->{values} or croak('No values for group');

    my $Group = MT->model('group');
    my $group = $Group->get_by_key( { name => $v->{name} } );

    $group->set_values($v);
    $group->status( $Group->ACTIVE() );
    $group->save or croak( $group->errstr );
    return $group;
}


=head2 create_entry

DOCUMENTATION NEEDED

=cut
sub create_entry {
    my $self     = shift;
    my ( $data ) = @_;
    my $v        = $data->{values} or croak('No values for entry');
    my $env_data = $self->env_data;

    my $author_key = delete $v->{author}
        or croak('No author key for entry!');
    my $author_id = $env_data->{users}{$author_key}{values}{id}
        or croak("Could not get author ID for $author_key for entry!");
    # my $author = $Author->load( $author_id )
    #     or croak("Could not load author ID $author_id!");
    $v->{author_id} = $author_id;

    my $blog_key = delete $v->{blog} or croak('No blog key for entry!');
    my $blog_id = $env_data->{blogs}{$blog_key}{values}{id}
        or croak ("Could not get blog $blog_key for entry!");
    $v->{blog_id} = $blog_id;

    my $Entry = MT->model('entry');
    my $entry = $Entry->get_by_key( { title => $v->{title} } );
    $entry->set_values($v);
    $entry->status( $Entry->RELEASE() );

    $entry->set_tags(@{ $v->{tags} }) if $v->{tags};

    $entry->save() or croak( $entry->errstr );

    return $entry;
}


=head2 init_test_blog

DOCUMENTATION NEEDED

=cut
sub init_test_blog {
    my $self    = shift;
    my $app     = MT->instance;
    my $basename = $self->test_basename();

    require MT::Util;

    my $blog = MT->model('blog')->get_by_key({
        name => $basename.' plugin test blog',
    });

    $app->config->DefaultSiteRoot
        or warn   "DefaultSiteRoot undefined in mt-config.cgi. "
                . "Test blog site path may be incorrect/invalid.";
    $blog->site_path(
        File::Spec->catdir( $app->config->DefaultSiteRoot, $basename ).'/'
    );

    $app->config->DefaultSiteURL
        or warn   "DefaultSiteURL undefined in mt-config.cgi. "
                . "Test blog site URL may be incorrect/invalid.";
    $blog->site_url(
        caturl( $app->config->DefaultSiteURL, $basename ).'/'
    );

    $blog->save();
    $self->blog( $blog );
}


=head2 init_test_user

DOCUMENTATION NEEDED

=cut
sub init_test_user {
    my $self       = shift;
    my $basename   = $self->test_basename();
    my $user_class = MT->model('author');
    my $user       = $user_class->get_by_key({
        name      => $basename."_test",
        nickname  => $basename." plugin test user",
        auth_type => 'MT',
        password  => '',
    })
        or die "Could not create or load test user: ".$user_class->errstr;

    $user->save
        or die "Could not save test user: ".$user->errstr;

    my $role = MT->model('role')->load({ name => 'Author' });
    MT->model('association')->link( $user => $role => $self->blog );

    $self->users([ $user, @{$self->users||[]} ]);
    $self->user( $user );
}

1;

__END__
