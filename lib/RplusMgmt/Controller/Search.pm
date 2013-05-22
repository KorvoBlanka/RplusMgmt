package RplusMgmt::Controller::Search;

use Mojo::Base 'Mojolicious::Controller';

sub index {
    my $self = shift;
    $self->render;
}

1;
