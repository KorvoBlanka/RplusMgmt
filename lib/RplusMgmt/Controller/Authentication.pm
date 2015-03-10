package RplusMgmt::Controller::Authentication;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Account;
use Rplus::Model::Account::Manager;
use Rplus::Model::User;
use Rplus::Model::User::Manager;

use JSON;
use Data::Dumper;

sub auth {
    my $self = shift;

    return 1 if $self->stash('user') && $self->stash('user')->{'id'} && $self->session_check($self->session->{'user'}->{id});

    $self->render(template => 'authentication/signin');
    return undef;
}

sub signin {
    my $self = shift;

    my $account_name = $self->param('account_name');
    my $login = $self->param_n('login');
    my $password = $self->param('password');
    my $remember_me = $self->param_b('remember_me');

    return $self->render(json => {status => 'failed', reason => 'no_data'}) unless $login && defined $password;

    my $account = Rplus::Model::Account::Manager->get_objects(
        query => [
            name => $account_name, del_date => undef
        ],
        require_objects => ['location'],
    )->[0];
    return $self->render(json => {status => 'failed', reason => 'account_not_found'}) unless $account;

    say $account->id;
    my $user = Rplus::Model::User::Manager->get_objects(query => [account_id => $account->id, login => $login, password => $password, delete_date => undef])->[0];
    return $self->render(json => {status => 'failed', reason => 'user_not_found'}) unless $user;

    return $self->render(json => {status => 'failed', reason => 'no_money'}) if $account->{balance} < 0;
    return $self->render(json => {status => 'failed', reason => 'user_limit'}) if $self->log_in_check($account->{user_count} * 1, $user->id) == 0;

    my $coords = from_json($account->location->map_coords);

    say Dumper $coords;

    $self->session->{'user'} = {
        account_name => $account_name,
        account_id => $account->{id},
        id => $user->id,
        login => $user->login,
        role => $user->role,

        mode => $account->mode,
        location_id => $account->location_id,
        city_guid => $account->location->city_guid,
        phone_prefix => $account->location->phone_prefix,
        map_lat => $coords->{lat},
        map_lng => $coords->{lng},
    };

    say Dumper $self->session->{'user'};

    $self->session(sid => int(rand(100000)));

    if ($remember_me) {
        $self->session(expiration => 28800);
    } else {
        $self->session(expiration => 3600); # default expiration
    }

    $self->log_in($user->id);

    return $self->render(json => {status => 'success', account_id => $account->{id}});
}

sub signout {
    my $self = shift;

    $self->log_out($self->session->{'user'}->{id});

    delete $self->session->{'user'};

    return $self->redirect_to('/');
}

1;
