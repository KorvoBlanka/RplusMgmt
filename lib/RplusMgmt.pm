package RplusMgmt;

use Mojo::Base 'Mojolicious';

our $VERSION = '1.0';

use Rplus::Model::Account;
use Rplus::Model::Account::Manager;
use Rplus::Model::User;
use Rplus::Model::User::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::DB;

use RplusMgmt::Task::SMS;
use RplusMgmt::Task::Subscriptions;
use RplusMgmt::Task::CalendarSync;
use RplusMgmt::Task::BillingSync;

use RplusMgmt::L10N;

use JSON;
use Hash::Merge;
use Scalar::Util qw(blessed);
use Mojo::Util qw(trim);
use DateTime::Format::Pg qw();
use DateTime::Format::Strptime qw();

use Time::HiRes qw( time usleep );
use Cache::FastMmap;
use POSIX;

my $fmap = Cache::FastMmap->new();
my $ua = Mojo::UserAgent->new;
# This method will run once at server start
sub startup {
    my $self = shift;

    $fmap->set('task_process', {});
    $fmap->set('users_online', {});
    $fmap->set('users_logged_in', {});
    $fmap->set('chat_msg', {});

    # Plugins
    my $config = $self->plugin('Config' => {file => 'app.conf'});

    # Secret
    $self->secrets($config->{secrets} || ($config->{secret} && [$config->{secret}]) || ['no secret defined']);

    # Default stash values
    $self->defaults(
        jquery_ver => '2.0.3',
        bootstrap_ver => '3.0.3',
        momentjs_ver => '2.8.2',
        holderjs_ver => '2.2.0',
        leafletjs_ver => '0.7.7',
        leafletjs_draw_ver => '0.2.3-dev',
        leafletjs_fullscreen_ver => '2013.10.14',
        typeaheadjs_ver => '0.9.4-dev',
        assets_url => $config->{assets}->{url} || '/assets',
    );

     $self->helper(new_message => sub {
        my ($self, $id, $from, $to) = @_;

        $fmap->set('chat_msg', {
            id => $id,
            from => $from,
            to => $to,
        });

        return;
    });

    $self->helper(is_user_online => sub {
        my ($self, $user_id) = @_;

        my $users_online = $fmap->get('users_online');

        return $users_online->{$user_id};
    });

    $self->helper(is_logged_in => sub {
        my ($self, $account_id, $user_id) = @_;

        my $login_struct = $fmap->get('users_logged_in');

        return 1 if $login_struct->{$account_id} && $login_struct->{$account_id}->{$user_id};
        return 0;
    });

    $self->helper(uc_check => sub {
        my ($self, $account_id, $user_id, $user_count) = @_;

        my $account = $self->get_account();
        return 0 unless $account;
        my $max_users = $account->user_count * 1;
        my $login_struct = $fmap->get('users_logged_in');

        if ($login_struct->{$account_id} && (scalar keys $login_struct->{$account_id}) > $user_count) {
            $login_struct->{$account_id} = {};
            $fmap->set('users_logged_in', $login_struct);
        }
        return 1 if $login_struct->{$account_id} && $login_struct->{$account_id}->{$user_id};
        if ($login_struct->{$account_id}) {
            return 0 if scalar keys $login_struct->{$account_id} >= $user_count;
        }

        return 1;
    });

    $self->helper(get_account => sub {
        my ($self) = @_;

        my $acc_name = $self->session('account_name');
        my $account = Rplus::Model::Account::Manager->get_objects(query => [name => $acc_name, del_date => undef])->[0];

        return $account;
    });

    $self->helper(session_check => sub {
        my ($self, $account_id, $user_id) = @_;

        #return 1 if $self->config->{account_type} eq 'demo' || $self->config->{account_type} eq 'dev';

        my $account = $self->get_account();
        return 0 unless $account;

        my $max_users = $account->user_count * 1;
        my $login_struct = $fmap->get('users_logged_in');

        return 0 if $account->balance < 0;
        return 0 unless exists $login_struct->{$account_id};
        return 0 unless exists $login_struct->{$account_id}->{$user_id};
        return 0 if $self->session->{sid} != $login_struct->{$account_id}->{$user_id};

        return 0 if scalar keys $login_struct->{$account_id} > $max_users;

        return 1;
    });

    $self->helper(log_in => sub {
        my ($self, $account_id, $user_id) = @_;

        my $login_struct = $fmap->get('users_logged_in');

        $login_struct->{$account_id} = {} unless $login_struct->{$account_id};
        $login_struct->{$account_id}->{$user_id} = $self->session->{sid};

        $fmap->set('users_logged_in', $login_struct);

        return;
    });

    $self->helper(log_out => sub {
        my ($self, $account_id, $user_id) = @_;

        my $login_struct = $fmap->get('users_logged_in');
        if ($login_struct->{$account_id} && $login_struct->{$account_id}->{$user_id}) {
            delete $login_struct->{$account_id}->{$user_id};
        }
        $fmap->set('users_logged_in', $login_struct);

        return;
    });

    # DB helper
    $self->helper(db => sub { Rplus::DB->new_or_cached });

    # JS Once helper
    $self->helper(js_once => sub {
        my ($self, $js_url) = @_;
        $self->stash('rplus.js_included' => {}) unless $self->stash('rplus.js_included');
        my $js_included = $self->stash('rplus.js_included');
        if (!$js_included->{$js_url}) {
            $js_included->{$js_url} = 1;

            return $self->render_to_string(inline => '<script type="application/javascript" src="<%= $js_url %>"></script>', js_url => $js_url);
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

            return $self->render_to_string(inline => '<link rel="stylesheet" href="<%= $css_url %>">', css_url => $css_url);
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

        my $c_phone_prefix = $self->config->{default_phone_prefix};
        $phone_prefix //= $c_phone_prefix;

        return $phone_num =~ s/^(\Q$phone_prefix\E)(\d+)$/($1)$2/r if $phone_prefix && $phone_num =~ /^\Q$phone_prefix\E/;
        return $phone_num =~ s/^(\d{3})(\d{3})(\d{4})/($1)$2$3/r;
    });

    # PhoneNum parser helper
    $self->helper(parse_phone_num => sub {
        my ($self, $phone_num, $phone_prefix) = @_;
        return undef unless $phone_num;

        my $c_phone_prefix = $self->config->{default_phone_prefix};
        $phone_prefix = $c_phone_prefix;

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
            from_json($value);
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

    # Hidden nav
    $self->helper(account_type => sub {
        my $account_type = $self->config->{account_type} || '';
        return $account_type;
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

    #
    $self->hook(before_routes => sub {
        my $c = shift;

        if (my $user_id = $c->session->{user_id}) {
            if (my $user = Rplus::Model::User::Manager->get_objects(query => [id => $user_id, delete_date => undef])->[0]) {
                $c->stash(user => {
                    id => $user->id,
                    login => $user->login,
                    name => $user->name,
                    role => $user->role,
                    phone_num => $user->phone_num,
                    add_date => $user->add_date,
                    subordinate => [$user->subordinate],
                    permissions => Hash::Merge->new('RIGHT_PRECEDENT')->merge($c->config->{roles}->{$user->role} || {}, from_json($user->permissions)),
                });
            }
        }
    });

    my $task_timer_id = Mojo::IOLoop->recurring(180 => sub {

      my $tp = $fmap->get('task_process');

      if (waitpid($tp->{pid}, WNOHANG) != 0) { # вернет 0 если еще не завершился, -1 если такого нет, pid если завершился
        if (my $task_pid = fork) {
          say 'task process forked';
          $fmap->set('task_process', {pid => $task_pid,});
        } else {

          say 'child: doing chords';
          RplusMgmt::Task::BillingSync::run();
          RplusMgmt::Task::CalendarSync::run();

          RplusMgmt::Task::Subscriptions::run($self);
          #RplusMgmt::Task::SMS::run();
          say 'child: done';

          exit(0);
        }
      } else {
        say 'child is running'
      }

    });

    # Router
    my $r = $self->routes;

    # API namespace

    $r->route('/api/user/set_google_token')->to(namespace => 'RplusMgmt::Controller::API', controller => 'user', action => 'set_google_token');

    $r->route('/api/:controller')->under->to(cb => sub {
        my $self = shift;

        return 1 if $self->session('account') && $self->stash('user') && $self->session_check($self->session('account')->{id}, $self->stash('user')->{id});
        $self->render(json => {error => 'Unauthorized'}, status => 401);
        return undef;
    })->route('/:action')->to(namespace => 'RplusMgmt::Controller::API');

    # Base namespace
    my $r2 = $r->route('/')->to(namespace => 'RplusMgmt::Controller');
    {
        # Authentication
        $r2->post('/signin')->to('authentication#signin');
        $r2->get('/signout')->to('authentication#signout');

        $r2->get('/events')->to(cb => sub {
            my $self = shift;
            my $pound_count = 0;

            # Increase inactivity timeout for connection a bit :)
            Mojo::IOLoop->stream($self->tx->connection)->timeout(0);

            my $user_id = $self->stash('user')->{id};

            my $users_online = $fmap->get('users_online');
            $users_online->{$user_id} = 1;
            $fmap->set('users_online', $users_online);

            # Change content type
            $self->res->headers->content_type('text/event-stream');
            my $last_msg_id = 0;

            my $timer_id_1 = Mojo::IOLoop->recurring(1 => sub {
                my $msg = $fmap->get('chat_msg');
                if ($msg && $msg->{id}) {
                    if ($last_msg_id == 0) {
                        $last_msg_id = $msg->{id};
                    }
                    if ($msg->{id} != $last_msg_id && ((!$msg->{to} && $msg->{from} != $user_id) || $msg->{to} == $user_id)) {
                        $last_msg_id = $msg->{id};
                        my $to = $msg->{to};
                        $self->write_chunk("event:chat_message\ndata: $to\n\n");
                    }
                }
            });

            my $timer_id_10 = Mojo::IOLoop->recurring(60 => sub {
                $self->write_chunk("event:heartbeat\ndata: pound $pound_count\n\n");
                $pound_count++;
            });

            # Unsubscribe from event again once we are done
            $self->on(finish => sub {
                my $self = shift;

                my $users_online = $fmap->get('users_online');
                $users_online->{$user_id} = 0;
                $fmap->set('users_online', $users_online);

                Mojo::IOLoop->remove($timer_id_1);
                Mojo::IOLoop->remove($timer_id_10);
            });
        });

        # Tasks
        $r2->get('/tasks/:action')->to(controller => 'tasks');
        # Backdoor
        $r2->get('/backdoor/:action')->to(controller => 'backdoor');

        my $r2b = $r2->under->to(controller => 'authentication', action => 'auth');

        # Main controller
        $r2b->get('/')->to(template => 'main/index');

        # Export controllers
        $r2b->route('/export')->to(namespace => 'RplusMgmt::Controller::Export')->post('/:controller')->to(action => 'index');

        # Other controllers
        $r2b->get('/:controller/:action')->to(action => 'index');
    }
}

1;
