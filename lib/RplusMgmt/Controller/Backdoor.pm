package RplusMgmt::Controller::Backdoor;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::IOLoop;

use Rplus::Model::Account;
use Rplus::Model::Account::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;
use Rplus::Model::User;
use Rplus::Model::User::Manager;
use Rplus::Model::Client;
use Rplus::Model::Client::Manager;
use Rplus::Model::Subscription;
use Rplus::Model::Subscription::Manager;
use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Photo;
use Rplus::Model::Photo::Manager;

use JSON;
use Data::Dumper;

sub delete_account {
    my $self = shift;
    
    my $email = $self->param('email');
    
    my $account = Rplus::Model::Account::Manager->get_objects(
        query => [email => $email, del_date => undef],
    )->[0];
    return $self->render(json => {status => 'failed', reason => 'account_not_found'}) unless $account;
    
    $account->del_date('now');
    $account->save;
    
    return $self->render(json => {status => 'success'})
}

sub create_account {
    my $self = shift;

    my $email = $self->param('email');
    my $name = $self->param('name');
    my $location_id = $self->param('location_id');

    my $options_str = '{';
    $options_str .= '"notifications":{"contact_info":"","company":"","login":"","msg-count":"14","email-smtp":"","email-user":"","password":"","email-password":"","active":false,"email-port":""},';
    $options_str .= '"multylisting":{"company-name":""},';
    $options_str .= '"export":{"farpost-agent-phone":false,"avito-phone":"","irr-email":"","vnh-agent-phone":false,"present-phones":"","vnh-phones":"","vnh-company":"","irr-agent-phone":false,"avito-email":"","irr-url":"","avito-company":"","present-descr":"5","irr-phones":"","farpost-phones":"","present-agent-phone":false,"avito-agent-phone":false},';
    $options_str .= '"import":{"rent-office":"true","rent-apartment_new":"true","sale-townhouse":"true","sale-apartment_new":true,"sale-land":"true","sale-room":true,"sale-house":"true","rent-room":"true","rent-other":"true","sale-cottage":"true","rent-apartment":"true","rent-cottage":"true","rent-dacha":"true","sale-office":"true","rent-house":"true","sale-apartment":true,"rent-apartment_small":"true","rent-townhouse":"true","sale-apartment_small":true,"sale-other":"true","sale-dacha":"true","rent-land":"true"}';
    $options_str .= '}';
    
    
    my $telephony_str = '{"sip_login":"user","sip_password":"000","sip_host":"host"}';
    
    my $account;
    
    # Begin transaction
    my $db = $self->db;
    $db->begin_work;
    
    eval {    
        $account = Rplus::Model::Account->new (
            email => $email,
            name => $name,
            location_id => $location_id,
        );
        $account->save;

        
        my $options = Rplus::Model::Option->new (
            options => $options_str,
            account_id => $account->id,
        );
        $options->save;   

        my $user = Rplus::Model::User->new (
            login => 'manager',
            password => '12345',
            role => 'top',
            name => 'manager',

            ip_telephony => $telephony_str,
            subordinate => Mojo::Collection->new,
            account_id => $account->id,
        );

        $user->save;
    } or do {
        $db->rollback;
        return $self->render(json => {status => 'fail'});
    };
    
    $db->commit;
    return $self->render(json => {status => 'success', account_id => $account->id});
}

sub list_users {
    my $self = shift;
    
    $self->res->headers->header('Access-Control-Allow-Origin' => 'http://billing.rplusmgmt.com');
    
    my $account_name = $self->param('account_name');
    
    my $account = Rplus::Model::Account::Manager->get_objects(
        query => [name => $account_name, del_date => undef],
    )->[0];
    return $self->render(json => {status => 'failed', reason => 'account_not_found'}) unless $account;

    my $res = {
        count => 0,
        list => [],
    };

    my $user_iter = Rplus::Model::User::Manager->get_objects_iterator(query => [account_id => $account->id, delete_date => undef], sort_by => 'role DESC');
    while (my $user = $user_iter->next) {
        if ($user->id != 10000) {
            my $x = {
                id => $user->id,
                login => $user->login,
                password => $user->password,
                role => $user->role,
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

    return $self->render(json => {status => 'success', data => $res});
}

sub reset_usr_pwd {
    my $self = shift;
    
    $self->res->headers->header('Access-Control-Allow-Origin' => 'http://billing.rplusmgmt.com');
    
    my $id = $self->param('id');
    my $user = Rplus::Model::User::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render(json => {status => 'fail'}) unless $user;
    
    $user->password('12345');
    $user->save;
    
    return $self->render(json => {status => 'success'});
}

=begin comment

sub add_account {
    my $self = shift;

    my $email = $self->param_n('email');
    my $password = $self->param('password');

    my $balance = $self->param('balance');
    my $user_count = $self->param('user_count');

    my $mode = $self->param('mode');
    my $location_id = $self->param('location_id');

    my $reg_date = $self->param('reg_date');

    my $name = $self->param('name');

    my $account = Rplus::Model::Account->new (
        email => $email,
        password => $password,
        balance => $balance,
        user_count => $user_count,
        mode => $mode,
        location_id => $location_id,
        reg_date => $reg_date,
        name => $name,
    );
    $account->save;

    return $self->render(json => {status => 'success', account_id => $account->id});
}

sub add_options {
    my $self = shift;

    my $account_name = $self->param_n('account_name');
    my $account = Rplus::Model::Account::Manager->get_objects(
        query => [name => $account_name, del_date => undef],
    )->[0];
    return $self->render(json => {status => 'failed', reason => 'account_not_found'}) unless $account;

    my $options_str = $self->param_n('options_str');

    my $options = Rplus::Model::Option->new (
        options => $options_str,
        account_id => $account->id,
    );
    $options->save;

    return $self->render(json => {status => 'success', options_id => $options->id});
}

sub add_user {
    my $self = shift;

    # Input params
    my $account_name = $self->param_n('account_name');
    my $account = Rplus::Model::Account::Manager->get_objects(
        query => [name => $account_name, del_date => undef],
    )->[0];
    return $self->render(json => {status => 'failed', reason => 'account_not_found'}) unless $account;

    my $login = $self->param('login');
    my $password = $self->param('password');
    my $role = $self->param('role');
    my $name = $self->param('name');
    my $phone_num = $self->param('phone_num');
    my $description = $self->param('description');
    my $public_name = $self->param('public_name');
    my $public_phone_num = $self->param('public_phone_num');
    my $photo_url = $self->param('photo_url');
    my @subordinates = $self->param('subordinates');

    my $sip = {};
    $sip->{sip_host} = $self->param('sip_host');
    $sip->{sip_login} = $self->param('sip_login');
    $sip->{sip_password} = $self->param('sip_password');

    my $user = Rplus::Model::User->new;

    # Save
    $user->login($login);
    $user->password($password);
    $user->role($role);
    $user->name($name);
    $user->phone_num($phone_num || undef);
    $user->description($description);
    $user->public_name($public_name);
    $user->public_phone_num($public_phone_num);
    $user->ip_telephony(to_json($sip));
    $user->photo_url($photo_url);
    $user->subordinate(Mojo::Collection->new);
    $user->account_id($account->id);

    $user->save;

    return $self->render(json => {status => 'success', user_id => $user->id});
}

sub add_client {
    my $self = shift;

    # Prepare data
    my $account_name = $self->param_n('account_name');
    my $account = Rplus::Model::Account::Manager->get_objects(
        query => [name => $account_name, del_date => undef],
    )->[0];
    return $self->render(json => {status => 'failed', reason => 'account_not_found'}) unless $account;

    my $name = $self->param_n('name');
    my $phone_num = $self->param('phone_num');
    my $email = $self->param_n('email');
    my $skype = $self->param_n('skype');
    my $description = $self->param_n('description');
    my $send_owner_phone = $self->param_b('send_owner_phone');
    my $color_tag_id = $self->param('color_tag_id');
    my $agent_id = $self->param('agent_id');
    my $subscription_offer_types = $self->param('subscription_offer_types');

    my $client = Rplus::Model::Client->new;

    # Save
    $client->name($name);
    $client->phone_num($phone_num);
    $client->email($email);
    $client->skype($skype);
    $client->description($description);
    $client->send_owner_phone($send_owner_phone);
    $client->agent_id($agent_id);
    $client->subscription_offer_types($subscription_offer_types);

    $client->account_id($account->id);

    $client->save;

    return $self->render(json => {status => 'success', client_id => $client->id,});
}

sub add_subscription {
    my $self = shift;

    # Prepare data
    my $account_name = $self->param_n('account_name');
    my $account = Rplus::Model::Account::Manager->get_objects(
        query => [name => $account_name, del_date => undef],
    )->[0];
    return $self->render(json => {status => 'failed', reason => 'account_not_found'}) unless $account;

    my $user_id = $self->param('user_id') || undef;
    my $client_id = $self->param('client_id');
    my $offer_type_code = $self->param('offer_type_code');
    my $add_date = $self->param('add_date');
    my $end_date = $self->param('end_date') || undef;
    my @queries = $self->param('queries[]');
    my $realty_limit = $self->param('realty_limit') || 20;
    my $send_owner_phone = $self->param_b('send_owner_phone');

    my $subscription = Rplus::Model::Subscription->new;

    $subscription->user_id($user_id);

    $subscription->client_id($client_id);
    $subscription->offer_type_code($offer_type_code);
    $subscription->queries(Mojo::Collection->new(@queries));
    $subscription->add_date($add_date);
    $subscription->end_date($end_date);
    $subscription->realty_limit($realty_limit);
    $subscription->send_owner_phone($send_owner_phone);

    $subscription->save;

    return $self->render(json => {status => 'success', subscription_id => $subscription->id,});
}

sub add_realty {
    my $self = shift;

    my $account_name = $self->param_n('account_name');
    my $account = Rplus::Model::Account::Manager->get_objects(
        query => [name => $account_name, del_date => undef],
    )->[0];
    return $self->render(json => {status => 'failed', reason => 'account_not_found'}) unless $account;

    # Fields to save
    my @fields = (
        'type_code', 'offer_type_code', 'state_code',
        'address_object_id', 'house_num', 'house_type_id', 'ap_num', 'ap_scheme_id',
        'rooms_count', 'rooms_offer_count', 'room_scheme_id',
        'floor', 'floors_count', 'levels_count', 'condition_id', 'balcony_id', 'bathroom_id',
        'square_total', 'square_living', 'square_kitchen', 'square_land', 'square_land_type',
        'description', 'owner_info', 'owner_price', 'work_info', 'agent_id', 'agency_price',
        'latitude', 'longitude', 'sublandmark_id', 'add_date', 'last_seen_date', 'change_date',
    );

    my %data;
    for (@fields) {
        $data{$_} = $self->param_n($_);
        $data{$_} =~ s/,/./ if $data{$_} && $_ =~ /^square_/;
        $data{$_} =~ s/,/./ if $data{$_} && $_ =~ /_price$/;
    }

    $data{owner_phones} = Mojo::Collection->new($self->param('owner_phones[]'));
    $data{export_media} = Mojo::Collection->new($self->param('export_media[]'));

    my $realty = Rplus::Model::Realty->new(
        creator_id => undef,
        agent_id => undef,
    );

    $realty->$_($data{$_}) for keys %data;
    $realty->change_date('now()');
    $realty->account_id($account->id);

    $realty->save;

    my @photos = $self->param('photos[]');

    for (my $i = 0; $i < scalar @photos; $i += 2) {
        my $photo = Rplus::Model::Photo->new;
        $photo->realty_id($realty->id);
        $photo->filename($photos[$i]);
        $photo->thumbnail_filename($photos[$i + 1]);
        $photo->save;       
    }

    return $self->render(json => {status => 'success', realty_id => $realty->id});
}

=end comment
=cut

1;
