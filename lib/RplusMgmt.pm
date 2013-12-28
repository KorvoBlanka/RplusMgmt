package RplusMgmt;

use Mojo::Base 'Mojolicious';

our $VERSION = '1.0';

use Rplus::Model::User;
use Rplus::Model::User::Manager;

use Rplus::DB;

use JSON;
use Hash::Merge;
use Scalar::Util qw(blessed);
use Mojo::Util qw(trim);
use DateTime::Format::Pg qw();
use DateTime::Format::Strptime qw();

use RplusMgmt::L10N;

# This method will run once at server start
sub startup {
    my $self = shift;

    # Plugins
    my $config = $self->plugin('Config' => {file => 'app.conf'});

    # Secret
    $self->secrets($config->{secrets} || ($config->{secret} && [$config->{secret}]) || ['no secret defined']);

    # Default stash values
    $self->defaults(
        jquery_ver => '2.0.3',
        bootstrap_ver => '3.0.3',
        momentjs_ver => '2.2.1',
        holderjs_ver => '2.2.0',
        leafletjs_ver => '0.7',
        leafletjs_draw_ver => '0.2.3-dev',
        leafletjs_fullscreen_ver => '2013.10.14',
        typeaheadjs_ver => '0.9.4-dev',
        assets_url => $config->{assets}->{url} || '/assets',
    );

    # DB helper
    $self->helper(db => sub { Rplus::DB->new_or_cached });

    # JS Once helper
    $self->helper(js_once => sub {
        my ($self, $js_url) = @_;
        $self->stash('rplus.js_included' => {}) unless $self->stash('rplus.js_included');
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
        $self->stash('rplus.css_included' => {}) unless $self->stash('rplus.css_included');
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

    $self->helper(parse_datetime_local => sub {
        my ($self, $str) = @_;
        return undef unless $str;
        my $dt = DateTime::Format::Strptime::strptime("%FT%T", $str);
        $dt->set_time_zone('local');
        return $dt;
    });

    # PhoneNum formatter helper
    $self->helper(format_phone_num => sub {
        my ($self, $phone_num, $phone_prefix) = @_;
        return undef unless $phone_num;
        $phone_prefix //= $self->config->{default_phone_prefix};
        return $phone_num =~ s/^(\Q$phone_prefix\E)(\d+)$/($1)$2/r if $phone_prefix && $phone_num =~ /^\Q$phone_prefix\E/;
        return $phone_num =~ s/^(\d{3})(\d{3})(\d{4})/($1)$2$3/r;
    });

    # PhoneNum parser helper
    $self->helper(parse_phone_num => sub {
        my ($self, $phone_num, $phone_prefix) = @_;
        return undef unless $phone_num;
        $phone_prefix //= $self->config->{default_phone_prefix};
        if ($phone_num !~ /^\d{10}$/) {
            $phone_num =~ s/\D//g;
            $phone_num =~ s/^(7|8)(\d{10})$/$2/;
            $phone_num = $phone_prefix.$phone_num if "$phone_prefix$phone_num" =~ /^\d{10}$/;
            return undef unless $phone_num =~ /^\d{10}$/;
        }
        return $phone_num;
    });

    # Validation checks
    $self->validator->add_check(is_phone_num => sub {
        my ($validation, $name, $value) = @_;
        return !$self->parse_phone_num($value);
    });

    $self->validator->add_check(is_datetime => sub {
        my ($validation, $name, $value, $format) = @_;
        eval {
            DateTime::Format::Strptime::strptime($format // "%FT%T%z", $value);
        } or do {
            return $@;
        };
        return 0;
    });

    $self->validator->add_check(is_json => sub {
        my ($self, $name, $value) = @_;
        eval {
            decode_json($value);
            1;
        } or do {
            return 1;
        };
        return 0;
    });

    # "Normalized" param helper
    $self->helper(param_n => sub {
        my ($self, $name) = @_;
        my $x = $self->param($name); $x = trim($x) || undef if defined $x;
        return $x;
    });

    # "Boolean" param helper
    $self->helper(param_b => sub {
        my ($self, $name) = @_;
        my $x = $self->param($name);
        return undef unless defined $x;
        return $x && lc($x) ne 'false' ? 1 : 0;
    });

    # Permissions
    $self->hook(before_routes => sub {
        my $c = shift;
        if (my $user_id = $c->session->{user}->{id}) {
            if (my $user = Rplus::Model::User::Manager->get_objects(query => [id => $user_id, delete_date => undef])->[0]) {
                $c->stash(user => {
                    id => $user->id,
                    login => $user->login,
                    name => $user->name,
                    role => $user->role,
                    phone_num => $user->phone_num,
                    add_date => $user->add_date,
                    permissions => Hash::Merge->new('RIGHT_PRECEDENT')->merge($c->config->{roles}->{$user->role} || {}, decode_json($user->permissions)),
                });
            }
        }
    });

    # Has permission helper
    $self->helper(has_permission => sub {
        my ($self, $module, $right) = (shift, shift, shift);
        return undef unless $self->stash('user');
        my $access = $self->stash('user')->{permissions}->{$module}->{$right};
        return 0 unless $access;
        if (@_ && ref($access) eq 'HASH') {
            my $user_id = shift;
            return $access->{nobody} unless $user_id;
            return $access->{others} unless $user_id == $self->stash('user')->{id};
        }
        return $access;
    });

    # Hidden nav
    $self->helper(is_hidden_nav => sub {
        my ($self, $nav) = @_;
        return undef unless $self->stash('user');
        my $hidden_navs = $self->config->{force_hide_nav}->{$self->stash('user')->{role}} || [];
        my %hidden_navs_h = (map { $_ => 1 } @$hidden_navs);
        return $hidden_navs_h{$nav};
    });

    # Localization
    my %lh = (map { $_ => RplusMgmt::L10N->get_handle($_) } qw(en ru));
    $self->helper(loc => sub {
        my $self = shift;
        my $lang = $self->config->{default_lang} || 'en';
        $lh{$lang}->maketext(@_);
    });

    # Ucfirst + localization
    $self->helper(ucfloc => sub {
        my $self = shift;
        ucfirst $self->loc(@_);
    });

    # Router
    my $r = $self->routes;

    # API namespace
    $r->route('/api/:controller')->bridge->to(cb => sub {
        my $self = shift;
        return 1 if $self->stash('user');
        $self->render(json => {error => 'Unauthorized'}, status => 401);
        return undef;
    })->route('/:action')->to(namespace => 'RplusMgmt::Controller::API');

    # Base namespace
    my $r2 = $r->route('/')->to(namespace => 'RplusMgmt::Controller');
    {
        # Authentication
        $r2->post('/signin')->to('authentication#signin');
        $r2->get('/signout')->to('authentication#signout');

        # Tasks
        $r2->get('/tasks/:action')->to(controller => 'tasks');

        my $r2b = $r2->bridge->to(controller => 'authentication', action => 'auth');

        # Main controller
        $r2b->get('/')->to(template => 'main/index');

        # Export controllers
        $r2b->route('/export')->to(namespace => 'RplusMgmt::Controller::Export')->post('/:controller')->to(action => 'index');

        # Other controllers
        $r2b->get('/:controller/:action')->to(action => 'index');
    }
}

1;
