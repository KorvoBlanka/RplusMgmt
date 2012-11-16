package RplusMgmt::Main;

use Mojo::Base 'Mojolicious::Controller';

use utf8;

sub index {
    my $self = shift;
    $self->render;
}

1;
