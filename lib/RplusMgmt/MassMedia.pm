package RplusMgmt::MassMedia;

use Mojo::Base 'Mojolicious::Controller';

use utf8;

use Rplus::Export::Present;
use Rplus::Export::VNX;

sub present {
    my $self = shift;
    $self->app->types->type(rtf => 'text/rtf');
    $self->render(data => Rplus::Export::Present::export2(), format => 'rtf');
}

sub vnx {
    my $self = shift;
    $self->app->types->type(xls => 'application/vnd.ms-excel');
    $self->render(data => Rplus::Export::VNX::export2(), format => 'xls');
}

1;
