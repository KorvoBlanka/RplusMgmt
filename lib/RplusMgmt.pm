package RplusMgmt;

use Mojo::Base 'Mojolicious';

our $VERSION = '1.0';

use Rplus::DB;

# This method will run once at server start
sub startup {
    my $self = shift;

    # Plugins
    $self->plugin('Config' => {file => 'app.conf'});

    # Secret
    $self->secret('fkj49SqZ1g1k2fqrq1g31SPgh449FqjrRfNqw4aquR3v4');

    # DB
    $self->helper(db => sub { Rplus::DB->new_or_cached });

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
        $r2b->get('/')->to(template => 'main/index');

        # Configuration controller
        $r2b->get('/conf/:action')->to(controller => 'configuration');

        # Export controllers
        $r2b->route('/export')->to(namespace => 'RplusMgmt::Controller::Export')->post('/:controller')->to(action => 'index');

        # Other controllers
        $r2b->get('/:controller/:action')->to(action => 'index');
    }

    # API namespace
    $r->route('/api')->to(namespace => 'RplusMgmt::Controller::API')->route('/:controller')->bridge->to(action => 'auth')->route('/:action');
}

1;
