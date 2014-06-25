package RplusMgmt::Controller::Authentication;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::User;
use Rplus::Model::User::Manager;

my $ua = Mojo::UserAgent->new;

sub auth {
    my $self = shift;

    my $tx = $ua->get('http://rplusmgmt.com/api/account/get_by_domain?subdomain=' . $self->config->{'subdomain'});
    my $acc_data;
    if (my $res = $tx->success) {
      $acc_data = $res->json;
    }

    return 1 if !$acc_data->{blocked} && $self->stash('user') && $self->stash('user')->{'id'} && $self->session_check($self->session->{'user'}->{login}, $acc_data->{user_count} * 1);

    $self->render(template => 'authentication/signin');
    return undef;
}

sub signin {
    my $self = shift;

    my $login = $self->param_n('login');
    my $password = $self->param('password');
    my $remember_me = $self->param_b('remember_me');

    my $tx = $ua->get('http://rplusmgmt.com/api/account/get_by_domain?subdomain=' . $self->config->{'subdomain'});
    my $acc_data;
    if (my $res = $tx->success) {
      $acc_data = $res->json;
    }

    return $self->render(json => {status => 'failed', reason => 'no_data'}) unless $login && defined $password;

    my $user = Rplus::Model::User::Manager->get_objects(query => [login => $login, password => $password, delete_date => undef])->[0];
    return $self->render(json => {status => 'failed', reason => 'not_found'}) unless $user;

    return $self->render(json => {status => 'failed', reason => 'not_found'}) unless $acc_data;
    return $self->render(json => {status => 'failed', reason => 'no_money'}) if $acc_data->{blocked} == 1;

    return $self->render(json => {status => 'failed', reason => 'user_limit'}) if $self->log_in_check($acc_data->{user_count} * 1, $login) == 0;

    $self->session->{'user'} = {
        id => $user->id,
        login => $user->login,
        role => $user->role,
        mode => $acc_data->{mode},
    };

    $self->session(sid => int(rand(100000)));

    if ($remember_me) {
        $self->session(expiration => 28800);
    } else {
        $self->session(expiration => 3600); # default expiration
    }

    $self->log_in($login);

    return $self->render(json => {status => 'success'});
}

sub signout {
    my $self = shift;

    $self->log_out($self->session->{'user'}->{login});

    delete $self->session->{'user'};

    return $self->redirect_to('/');
}

1;
