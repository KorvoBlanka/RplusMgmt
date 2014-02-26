package RplusMgmt::Controller::Authentication;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::User;
use Rplus::Model::User::Manager;

my $ua = Mojo::UserAgent->new;

sub auth {
    my $self = shift;

    #my $tx = $ua->get('http://test.dvnic.com/api/account/get_by_domain?subdomain=account92');
    #my $acc_data;
    #if (my $res = $tx->success) {
    #  $acc_data = $res->json;
    #}

    #return 1 if $acc_data->{blocked} == 0 && $acc_data->{balance} > 0 && $self->stash('user') && $self->stash('user')->{'id'};
    return 1 if $self->stash('user') && $self->stash('user')->{'id'};

    $self->render(template => 'authentication/signin');
    return undef;
}

sub signin {
    my $self = shift;

    my $login = $self->param_n('login');
    my $password = $self->param('password');
    my $remember_me = $self->param_b('remember_me');

    return $self->render(json => {status => 'failed'}) unless $login && defined $password;

    my $user = Rplus::Model::User::Manager->get_objects(query => [login => $login, password => $password, delete_date => undef])->[0];
    return $self->render(json => {status => 'failed'}) unless $user;

    $self->session->{'user'} = {
        id => $user->id,
        login => $user->login,
        role => $user->role,
    };

    if ($remember_me) {
        $self->session(expiration => 604800);
    } else {
        $self->session(expiration => 3600); # default expiration
    }

    return $self->render(json => {status => 'success'});
}

sub signout {
    my $self = shift;

    delete $self->session->{'user'};

    return $self->redirect_to('/');
}

1;
