package RplusMgmt;

use Mojo::Base 'Mojolicious';

our $VERSION = '1.0';

use Rplus::DB;

use Scalar::Util qw(blessed);
use DateTime::Format::Pg qw();
use DateTime::Format::Strptime qw();
use Rplus::Util::PhoneNum;

# This method will run once at server start
sub startup {
    my $self = shift;

    # Plugins
    my $config = $self->plugin('Config' => {file => 'app.conf'});

    # Secret
    $self->secret($config->{secret}) if $config->{secret};

    # Default stash values
    $self->defaults(
        jquery_ver => '2.0.3',
        bootstrap_ver => '3.0.2',
        assets_url => $config->{assets}->{url} || '/assets',
    );

    # DB helper
    $self->helper(db => sub { Rplus::DB->new_or_cached });

    # JS Once helper
    $self->helper(js_once => sub {
        my ($self, $js_url) = @_;
        $self->stash('rplus.js_included' => {}) unless $self->stash->{'rplus.js_included'};
        my $js_included = $self->stash('rplus.js_included');
        if (!$js_included->{$js_url}) {
            $js_included->{$js_url} = 1;
            return $self->render(partial => 1, inline => '<script type="application/javascript" src="<%= $js_url %>"></script>', js_url => $js_url);
        }
        return;
    });

    # CSS Once helper
    $self->helper(css_once => sub {
        my ($self, $css_url) = @_;
        $self->stash('rplus.css_included' => {}) unless $self->stash->{'rplus.css_included'};
        my $css_included = $self->stash('rplus.css_included');
        if (!$css_included->{$css_url}) {
            $css_included->{$css_url} = 1;
            return $self->render(partial => 1, inline => '<link rel="stylesheet" href="<%= $css_url %>">', css_url => $css_url);
        }
        return;
    });

    # DateTime formatter helper
    $self->helper(format_datetime => sub {
        my ($self, $dt) = @_;
        return undef unless $dt;
        $dt = DateTime::Format::Pg->parse_timestamptz($dt) unless blessed $dt;
        return $dt->strftime('%FT%T%z');
    });

    # DateTime parser helper
    $self->helper(parse_datetime => sub {
        my ($self, $str) = @_;
        return undef unless $str;
        return DateTime::Format::Strptime::strptime("%FT%T%z", $str);
    });

    # Validation checks
    $self->validator->add_check(is_phone => sub {
        my ($validation, $name, $value) = @_;
        return !Rplus::Util::PhoneNum->parse($value);
    });

    $self->validator->add_check(is_datetime => sub {
        my ($validation, $name, $value) = @_;
        eval {
            DateTime::Format::Strptime::strptime("%FT%T%z", $value);
        } or do {
            return $@;
        };
        return 0;
    });

    # Router
    my $r = $self->routes;

    # API
    $r->route('/api/:controller')->bridge->to(cb => sub {
        my $self = shift;

        if (my $user_role = $self->session->{user}->{role}) {
            my $controller = $self->stash('controller');
            if (my $controller_role_conf = $self->config->{roles}->{$user_role}->{$controller}) {
                $self->stash(controller_role_conf => $controller_role_conf);
                $self->stash(user_role => $user_role);
                return 1;
            }
            #$self->render(json => {status => 'Forbidden'}, status => 403);
            #return undef;
        }
        return 1;

        $self->render(json => {status => 'Unauthorized'}, status => 401);
        return undef;
    })->route('/:action')->to(namespace => 'RplusMgmt::Controller::API');

    # Base namespace
    my $r2 = $r->route('/')->to(namespace => 'RplusMgmt::Controller');
    {
        # Authentication
        $r2->post('/signin')->to('authentication#signin');
        $r2->get('/signout')->to('authentication#signout');

        # Task
        $r2->get('/task/:action')->to(controller => 'task');

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
}

1;
