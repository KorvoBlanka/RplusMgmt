package RplusMgmt::Controller::API::User;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::User;
use Rplus::Model::User::Manager;

use JSON;
use Rplus::Util::PhoneNum;
use Mojo::Util qw(trim);

sub auth {
    my $self = shift;

    #my $user_role = $self->session->{'user'}->{'role'};
    #if ($user_role && $self->config->{'roles'}->{$user_role}->{'configuration'}->{'landmarks'}) {
    #    return 1;
    #}
    return 1;

    $self->render_not_found;
    return undef;
}

sub list {
    my $self = shift;

    my $res = {
        count => 0,
        list => [],
    };

    my $user_iter = Rplus::Model::User::Manager->get_objects_iterator(query => [delete_date => undef], sort_by => 'name');
    while (my $user = $user_iter->next) {
        my $x = {
            id => $user->id,
            login => $user->login,
            role => $user->role,
            name => $user->name,
            phone_num => $user->phone_num,
            description => $user->description,
            add_date => $user->add_date,
        };
        push @{$res->{list}}, $x;
    }
    $res->{count} = scalar @{$res->{list}};

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    my $id = $self->param('id');

    my $user = Rplus::Model::User::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render_not_found unless $user;

    my $meta = decode_json($user->metadata);
    my $res = {
        id => $user->id,
        login => $user->login,
        password => $user->password,
        role => $user->role,
        name => $user->name,
        phone_num => $user->phone_num,
        description => $user->description,
        add_date => $user->add_date,
        public_name => $meta->{public_name},
        public_phone_num => $meta->{public_phone_num},
    };

    return $self->render(json => $res);
}

sub save {
    my $self = shift;

    no warnings 'uninitialized';

    my $user;
    if (my $id = $self->param('id')) {
        $user = Rplus::Model::User::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    } else {
        $user = Rplus::Model::User->new;
    }
    return $self->render_not_found unless $user;

    # Validate role
    return $self->render(json => {status => 'failed'}) unless exists $self->config->{roles}->{scalar($self->param('role')) || 'unknown'};

    my $meta = decode_json($user->metadata);
    for my $f (qw(name login password role description)) {
        $user->$f(trim(scalar($self->param($f))) || undef);
    }
    $user->phone_num(Rplus::Util::PhoneNum->parse(scalar $self->param('phone_num')));

    for my $f (qw(public_name public_phone_num)) {
        $meta->{$f} = trim($self->param($f)) || undef;
    }
    $user->metadata(encode_json($meta));

    eval {
        $user->save;
        1;
    } or do {
        return $self->render(json => {status => 'failed'});
    };

    return $self->render(json => {status => 'success'});
}

1;
