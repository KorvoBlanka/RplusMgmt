package RplusMgmt::Controller::Authentication;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::User;
use Rplus::Model::User::Manager;

sub auth {
    my $self = shift;

    if ($self->session->{'user'}->{'id'}) {
        $self->stash(user_role => $self->session->{'user'}->{'role'});
        return 1;
    }

    $self->render(template => 'authentication/signin');
    return undef;
}

sub signin {
    my $self = shift;

    my $login = $self->param('login');
    my $password = $self->param('password');
    my $remember_me = $self->param('remember_me');

    my $user = Rplus::Model::User::Manager->get_objects(query => [ login => $login, password => $password, delete_date => undef ])->[0];
    return $self->render(json => {status => 'failed'}) unless $user;

    $self->session->{'user'} = {
        id => $user->id,
        login => $user->login,
        name => $user->name,
        role => $user->role,
        metadata => $user->metadata,
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
