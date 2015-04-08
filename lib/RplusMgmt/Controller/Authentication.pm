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

    my $login = $self->param_n('login');
    my $password = $self->param('password');
    my $remember_me = $self->param_b('remember_me');
    
    return $self->render(json => {status => 'failed', reason => 'no_data'}) unless $login && defined $password;

    my $acc_data = $self->get_acc_data();
    return $self->render(json => {status => 'failed', reason => 'account_not_found'}) unless $acc_data->{id};

    my $user = Rplus::Model::User::Manager->get_objects(query => [account_id => $acc_data->{id}, login => $login, password => $password, delete_date => undef])->[0];
    return $self->render(json => {status => 'failed', reason => 'user_not_found'}) unless $user;

    return $self->render(json => {status => 'failed', reason => 'no_money'}) if $acc_data->{balance} < 0;
    #return $self->render(json => {status => 'failed', reason => 'user_limit'}) if $self->log_in_check($acc_data->{user_count} * 1, $user->id) == 0;

    $self->session->{'user'} = {
        account_name => $acc_data->{name},
        account_id => $acc_data->{id},

        id => $user->id,
        login => $user->login,
        role => $user->role,

        mode => $acc_data->{mode},
        location_id => $acc_data->{location_id},
        
        phone_prefix => '4212',
        city_guid => 'a4859da8-9977-4b62-8436-4e1b98c5d13f',
        
        map_lat => 48.480232846617845,
        map_lng => 135.07203340530396,
    };

    $self->session(sid => int(rand(100000)));

    if ($remember_me) {
        $self->session(expiration => 28800);
    } else {
        $self->session(expiration => 3600); # default expiration
    }

    $self->log_in($user->id);

    return $self->render(json => {status => 'success', account_id => $acc_data->{id}});
}

sub signout {
    my $self = shift;

    $self->log_out($self->session->{'user'}->{id});

    delete $self->session->{'user'};

    return $self->redirect_to('/');
}

1;
