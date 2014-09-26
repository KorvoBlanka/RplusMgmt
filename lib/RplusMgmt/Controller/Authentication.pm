package RplusMgmt::Controller::Authentication;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::User;
use Rplus::Model::User::Manager;

use JSON;

sub auth {
    my $self = shift;

    return 1 if $self->stash('user') && $self->stash('user')->{'id'} && $self->session_check($self->session->{'user'}->{id});

    $self->render(template => 'authentication/signin');
    return undef;
}

sub signin {
    my $self = shift;

    my $login = $self->param_n('login');
    my $password = $self->param('password');
    my $remember_me = $self->param_b('remember_me');

    my $acc_data = $self->get_acc_data();

    return $self->render(json => {status => 'failed', reason => 'no_data'}) unless $login && defined $password;

    my $user = Rplus::Model::User::Manager->get_objects(query => [login => $login, password => $password, delete_date => undef])->[0];

    return $self->render(json => {status => 'failed', reason => 'no_connection'}) if $acc_data->{no_connection} == 1;
    return $self->render(json => {status => 'failed', reason => 'not_found'}) unless $user;
    return $self->render(json => {status => 'failed', reason => 'not_found'}) unless $acc_data;
    return $self->render(json => {status => 'failed', reason => 'no_money'}) if $acc_data->{blocked} == 1;
    return $self->render(json => {status => 'failed', reason => 'user_limit'}) if $self->log_in_check($acc_data->{user_count} * 1, $user->id) == 0;

    $self->session->{'user'} = {
        id => $user->id,
        login => $user->login,
        role => $user->role,
        mode => $acc_data->{mode},

        location_id => $acc_data->{location_id},
        city_guid => $acc_data->{city_guid},
        phone_prefix => $acc_data->{phone_prefix},
        map_lat => $acc_data->{map_lat},
        map_lng => $acc_data->{map_lng},
    };

    $self->session(sid => int(rand(100000)));

    if ($remember_me) {
        $self->session(expiration => 28800);
    } else {
        $self->session(expiration => 3600); # default expiration
    }

    $self->log_in($user->id);

    return $self->render(json => {status => 'success'});
}

sub signout {
    my $self = shift;

    $self->log_out($self->session->{'user'}->{id});

    delete $self->session->{'user'};

    return $self->redirect_to('/');
}

1;
