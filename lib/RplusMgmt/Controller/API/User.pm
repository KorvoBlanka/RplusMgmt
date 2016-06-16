package RplusMgmt::Controller::API::User;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::User;
use Rplus::Model::User::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Client;
use Rplus::Model::Client::Manager;

use Rplus::Util::GoogleCalendar;

use Mojo::Collection;
use File::Path qw(make_path);
use Image::Magick;

use JSON;


sub list {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(users => 'manage');

    my $res = {
        count => 0,
        list => [],
    };

    my $acc_id = $self->session('account')->{id};
    my $user_iter = Rplus::Model::User::Manager->get_objects_iterator(query => [account_id => $acc_id, delete_date => undef], sort_by => 'name');
    while (my $user = $user_iter->next) {
        if ($user->id != 10000) {
            my $x = {
                id => $user->id,
                login => $user->login,
                role => $user->role,
                role_loc => $self->ucfloc($user->role),
                name => $user->name,
                phone_num => $user->phone_num,
                description => $user->description,
                add_date => $self->format_datetime($user->add_date),
                photo_url => $user->photo_url ? $user->photo_url : '',
                offer_mode => $user->offer_mode,
            };
            push @{$res->{list}}, $x;
        }
    }

    $res->{count} = scalar @{$res->{list}};

    return $self->render(json => $res);
}

sub list_candidates {
    my $self = shift;

    my $res = {
        candidates => [],
    };

    my $acc_id = $self->session('account')->{id};
    my @owned = ();
    for my $m (@{Rplus::Model::User::Manager->get_objects(query => [account_id => $acc_id, role => 'manager', delete_date => undef])}) {
        push @owned, @{$m->subordinate};
    }

    for my $a (@{Rplus::Model::User::Manager->get_objects(query => [account_id => $acc_id, role => ['agent'], delete_date => undef], sort_by => 'name')}) {
        unless ($a->id ~~ @owned) {
            push @{$res->{candidates}}, {id => $a->id, name => $a->name,} unless $a->id == 10000;
        }
    }

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(users => 'manage');

    my $id = $self->param('id');

    my $acc_id = $self->session('account')->{id};
    my $user = Rplus::Model::User::Manager->get_objects(query => [account_id => $acc_id, id => $id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $user;

    my $sip = from_json($user->ip_telephony);
    my $res = {
        id => $user->id,
        login => $user->login,
        role => $user->role,
        role_loc => $self->ucfloc($user->role),
        name => $user->name,
        phone_num => $user->phone_num,
        description => $user->description,
        add_date => $self->format_datetime($user->add_date),
        public_name => $user->public_name,
        public_phone_num => $user->public_phone_num,
        sip_host => $sip->{sip_host} ? $sip->{sip_host} : '',
        sip_login => $sip->{sip_login} ? $sip->{sip_login} : '',
        sip_password => $sip->{sip_password} ? $sip->{sip_password} : '',
        photo_url => $user->photo_url ? $user->photo_url : '',
        offer_mode => $user->offer_mode,
        sync_google => $user->sync_google,
        candidates => [],
        subordinates => [],
    };

    for my $a (@{Rplus::Model::User::Manager->get_objects(query => [role => ['agent'], delete_date => undef], sort_by => 'name')}) {
        push @{$res->{candidates}}, {id => $a->id, name => $a->name,} unless $a->id == 10000;
    }

    if (scalar(@{$user->subordinate})) {
        for my $a (@{Rplus::Model::User::Manager->get_objects(query => [account_id => $acc_id, id => [$user->subordinate], delete_date => undef], sort_by => 'name')}) {
            push @{$res->{subordinates}}, {id => $a->id, name => $a->name,};
        }
    }

    return $self->render(json => $res);
}

sub find {
    my $self = shift;

    my $raw_phone_num = $self->param('phone_num');
    my $phone_num = $self->parse_phone_num($raw_phone_num);

    my $acc_id = $self->session('account')->{id};
    my $user;
    if ($phone_num) {
        $user = Rplus::Model::User::Manager->get_objects(query => [account_id => $acc_id, phone_num => $phone_num, delete_date => undef])->[0];
    }
    unless ($user) {
        my $user_iter = Rplus::Model::User::Manager->get_objects_iterator(query => [account_id => $acc_id, delete_date => undef], sort_by => 'name');
        while (my $x = $user_iter->next) {
            my $sip = from_json($x->ip_telephony);
            if ($sip->{sip_login} && $sip->{sip_login} eq $raw_phone_num) {
                $user = $x;
                last;
            }
        }
    }

    return $self->render(json => {error => 'Not Found'}, status => 404) unless $user;

    my $sip = from_json($user->ip_telephony);
    my $res = {
        id => $user->id,
        login => $user->login,
        role => $user->role,
        role_loc => $self->ucfloc($user->role),
        name => $user->name,
        phone_num => $user->phone_num,
        description => $user->description,
        add_date => $self->format_datetime($user->add_date),
        public_name => $user->public_name,
        public_phone_num => $user->public_phone_num,
        sip_host => $sip->{sip_host} ? $sip->{sip_host} : '',
        sip_login => $sip->{sip_login} ? $sip->{sip_login} : '',
        sip_password => $sip->{sip_password} ? $sip->{sip_password} : '',
        photo_url => $user->photo_url ? $user->photo_url : '',
    };

    return $self->render(json => $res);
}

sub save {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(users => 'manage');
    return $self->render(json => {error => 'Forbidden'}, status => 403) if ($self->account_type() eq 'demo');

    my $acc_id = $self->session('account')->{id};
    # Retrieve user
    my $user;
    if (my $id = $self->param('id')) {
        $user = Rplus::Model::User::Manager->get_objects(query => [account_id => $acc_id, id => $id, delete_date => undef])->[0];
    } else {
        $user = Rplus::Model::User->new;
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $user;

    # Input validation
    $self->validation->required('login');
    $self->validation->required('role')->in(keys %{$self->config->{roles}});
    $self->validation->required('name');
    $self->validation->optional('phone_num')->is_phone_num;

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {login => 'Invalid value'} if $self->validation->has_error('login');
        push @errors, {role => 'Invalid value'} if $self->validation->has_error('role');
        push @errors, {name => 'Invalid value'} if $self->validation->has_error('name');
        push @errors, {phone_num => 'Invalid value'} if $self->validation->has_error('phone_num');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

	if (Rplus::Model::User::Manager->get_objects_count(query => [account_id => $acc_id, '!id' => $user->id, login => $self->param_n('login'), delete_date => undef]) > 0) {
		return $self->render(json => {error => 'bad_login'}, status => 200)
	}

    # Input params
    my $login = $self->param_n('login');
    my $password = $self->param_n('password');
    my $role = $self->param('role');
    my $name = $self->param_n('name');
    my $phone_num = $self->parse_phone_num(scalar $self->param('phone_num'));
    my $description = $self->param_n('description');
    my $public_name = $self->param_n('public_name');
    my $public_phone_num = $self->param_n('public_phone_num');
    my $photo_url = $self->param_n('photo_url');

    my @subordinates = $self->param('subordinates[]');

    my $sip = {};
    $sip->{sip_host} = $self->param_n('sip_host');
    $sip->{sip_login} = $self->param_n('sip_login');
    $sip->{sip_password} = $self->param_n('sip_password');

    if ($user->role eq 'top' && $role ne 'top') {
        my $top_count = Rplus::Model::User::Manager->get_objects_count(query => [account_id => $acc_id, role => 'top', delete_date => undef]);
        return $self->render(json => {error => 'last_top'}, status => 200) if $top_count < 2;
    }

    # Save
    $user->login($login);
    $user->password($password) if $password;
    $user->role($role);
    $user->name($name);
    $user->phone_num($phone_num);
    $user->description($description);
    $user->public_name($public_name);
    $user->public_phone_num($public_phone_num);
    $user->ip_telephony(encode_json($sip));
    $user->photo_url($photo_url);
    $user->subordinate(Mojo::Collection->new(@subordinates)->compact->uniq);
    $user->account_id($acc_id);

    if (scalar(@subordinates) > 0 && $role ne 'manager') {
        $user->subordinate([]);
    }

    # если пользователь не агент он не может быть в подчиненных
    if ($user->id) {
        if ($role ne 'agent') {
            my $user_iter = Rplus::Model::User::Manager->get_objects_iterator(
                query => [
                    account_id => $acc_id,
                    role => 'manager',
                    \("subordinate && '{".$user->id."}'"),
                    delete_date => undef,
                ],
            );
            while (my $u = $user_iter->next) {
                my $s = Mojo::Collection->new(@{$u->subordinate});
                $s = $s->grep( sub {$_ != $user->id});
                $u->subordinate($s->compact->uniq);
                $u->save(changes_only => 1);
            }
        }
    }

    if ($user->id && $role eq 'dispatcher') {
        my $realty_count = Rplus::Model::Realty::Manager->get_objects_count(query => [agent_id => $user->id, delete_date => undef]);
        return $self->render(json => {error => 'Has Realty'}, status => 200) if $realty_count > 0;

        my $client_count = Rplus::Model::Client::Manager->get_objects_count(query => [agent_id => $user->id, delete_date => undef]);
        return $self->render(json => {error => 'Has Clients'}, status => 200) if $client_count > 0;
    }

    eval {
        $user->save($user->id ? (changes_only => 1) : (insert => 1));
        1;
    } or do {
        return $self->render(json => {error => $@}, status => 500);
    };

    return $self->render(json => {msg => 'success'}, status => 200);
}

sub upload_photo {
    my $self = shift;

    #return $self->render(json => {error => 'Limit is exceeded'}, status => 500) if $self->req->is_limit_exceeded;
    my $photo_url = '';
    my $cat = '/users/photos/';

    if (my $file = $self->param('files[]')) {
        my $path = $self->config->{'storage'}->{'path'} . '/' . $self->session('account')->{name} . $cat;
        my $name = (Time::HiRes::time =~ s/\.//r) . '.png'; # Unique name

        eval {
            make_path($path);
            $file->move_to($path . $name);

            # Convert image to jpeg
            my $image = Image::Magick->new;
            $image->Read($path . $name);
            $image->Resize(geometry => '800x800');
            $image->Extent(geometry => '800x800', gravity => 'Center', background => 'transparent');
            $image->Write($path . $name);

            # Save
            $photo_url = $cat . $name;

        } or do {
            return $self->render(json => {error => $@}, status => 500);
        };

        return $self->render(json => {status => 'success', photo_url => $photo_url, src => $self->config->{'storage'}->{'url'} . '/' . $self->session('account')->{'name'} . $photo_url});
    }

    return $self->render(json => {error => 'Bad Request'}, status => 400);
}

sub delete {
    my $self = shift;
    my $acc_id = $self->session('account')->{id};
    my $id = $self->param('id');

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(users => 'manage');
    return $self->render(json => {error => 'Forbidden'}, status => 403) if ($self->account_type() eq 'demo');

    my $user = Rplus::Model::User::Manager->get_objects(query => [account_id => $acc_id, id => $id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $user;

    if ($user->role eq 'top') {
        my $top_count = Rplus::Model::User::Manager->get_objects_count(query => [account_id => $acc_id, role => 'top', delete_date => undef]);
        return $self->render(json => {error => 'last_top'}, status => 200) if $top_count < 2;
    }

    my $realty_count = Rplus::Model::Realty::Manager->get_objects_count(query => [agent_id => $id, delete_date => undef]);
    return $self->render(json => {error => 'Has Realty'}, status => 200) if $realty_count > 0;

    my $client_count = Rplus::Model::Client::Manager->get_objects_count(query => [agent_id => $id, delete_date => undef]);
    return $self->render(json => {error => 'Has Clients'}, status => 200) if $client_count > 0;

    my $subordinate_count =  scalar @{$user->subordinate};
    return $self->render(json => {error => 'Has Subordinate'}, status => 200) if $subordinate_count > 0;

    $user->delete_date('now()');
    $user->save();

    return $self->render(json => {status => 'success'});
}

sub set_offer_mode {
    my $self = shift;

    my $id = $self->param('id');
    my $offer_mode = $self->param('offer_mode');

    my $acc_id = $self->session('account')->{id};
    my $user = Rplus::Model::User::Manager->get_objects(query => [account_id => $acc_id, id => $id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $user;

    $user->offer_mode($offer_mode);
    $user->save(changes_only => 1);

    return $self->render(json => {status => 'success'});
}

sub set_google_token {
    my $self = shift;
    my $id = $self->param('id');
    my $refresh_token = $self->param('refresh_token');

    Rplus::Util::GoogleCalendar::setRefreshToken($id, $refresh_token);
    return $self->render(json => {status => 'success'});
}

sub set_sync_google {
    my $self = shift;
    my $user_id = $self->param('user_id');
    my $val = $self->param('val');

    my $acc_id = $self->session('account')->{id};
    my $user = Rplus::Model::User::Manager->get_objects(query => [account_id => $acc_id, id => $user_id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $user;

    $user->sync_google($val);
    $user->save(changes_only => 1);

    Rplus::Util::GoogleCalendar::setGoogleData($user_id, {});

    return $self->render(json => {status => 'success'});
}

1;
