package RplusMgmt;

use Mojo::Base 'Mojolicious';

use utf8;

our $VERSION = '1.0';

# This method will run once at server start
sub startup {
    my $self = shift;

    # Router
    my $r = $self->routes;

    # Main controller
    $r->get('/')->to('main#index');

    # MassMedia export
    $r->get('/export/present.rtf')->to('mass_media#present');
    $r->get('/export/vnx.xls')->to('mass_media#vnx');

    # Common route
    $r->route('/:controller/:action')->to(action => 'index');
}

1;
