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

    return 1 if $self->session('account') && $self->stash('user') && $self->session_check($self->session('account')->{id}, $self->stash('user')->{id});

    $self->render(template => 'authentication/signin');
    return undef;
}

sub signin {
    my $self = shift;

    my $account_name = $self->param_n('account');
    my $login = $self->param_n('login');
    my $password = $self->param('password');
    my $remember_me = $self->param_b('remember_me');
    my $msg = '';

    $self->session(account_name => $account_name);

    return $self->render(json => {status => 'failed', reason => 'no_data'}) unless $login && defined $password;

    my $account = $self->get_account($account_name);
    return $self->render(json => {status => 'failed', reason => 'account_not_found'}) unless $account;

    my $user = Rplus::Model::User::Manager->get_objects(query => [account_id => $account->{id}, login => $login, password => $password, delete_date => undef])->[0];
    return $self->render(json => {status => 'failed', reason => 'user_not_found'}) unless $user;

    return $self->render(json => {status => 'failed', reason => 'no_money'}) if $account->{balance} < 0;
    return $self->render(json => {status => 'failed', reason => 'user_limit'}) if $self->uc_check($account->id, $user->id, $account->user_count * 1) == 0;

    $msg = 'Пользователь с таким логином уже вошел в систему' if $self->is_logged_in($user->account_id, $user->id);

    $self->session(sid => int(rand(100000)));
    $self->session(user_id => $user->id);

    $self->session(account => {
        id => $account->id,
        name => $account->name,
        mode => $account->mode,
        location_id => $account->location_id,
    });

    if ($remember_me) {
        $self->session(expiration => 28800);
    } else {
        $self->session(expiration => 3600); # default expiration
    }

    $self->log_in($account->id, $user->id);

    return $self->render(json => {status => 'success', message => $msg, account_id => $account->{id}});
}

sub signout {
    my $self = shift;

    if ($self->session('account') && $self->stash('user')) {
      $self->log_out($self->session('account')->{id}, $self->stash('user')->{id});
      delete $self->session->{'account'};
    }

    return $self->redirect_to('/');
}

1;
