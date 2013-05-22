package RplusMgmt;

use Mojo::Base 'Mojolicious';

our $VERSION = '1.0';

# This method will run once at server start
sub startup {
    my $self = shift;

    # Plugins
    $self->plugin('PoweredBy' => (name => "RplusMgmt $VERSION"));
    $self->plugin('Config' => {file => 'app.conf'});

    # Secret
    $self->secret('fkj49SqZ11dkG42fq1g31SAxPgh49FqjrRfN44aquR3v4');

    # Router
    my $r = $self->routes;

    # Base namespace
    my $r2 = $r->route('/')->to(namespace => 'RplusMgmt::Controller');
    {
        # Authentication
        $r2->post('/signin')->to('authentication#signin');
        $r2->get('/signout')->to('authentication#signout');

        my $r2b = $r2->bridge->to(controller => 'authentication', action => 'auth');

        # Main controller
        $r2b->get('/')->to('main#index');

        # MassMedia export
        #$r->get('/export/present.rtf')->to('mass_media#present');
        #$r->get('/export/vnx.xls')->to('mass_media#vnx');

        $r2b->route('/:controller/:action')->to(action => 'index');
    }

    # API namespace
    my $r3 = $r->route('/api')->to(namespace => 'RplusMgmt::Controller::API');
    {
        $r3->route('/:controller')->bridge->to(action => 'auth')->route('/:action');
    }
}

1;
